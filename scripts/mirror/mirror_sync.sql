-- Prod -> dev nightly mirror of the whatsfresh schema (Task 609).
-- Catalog-driven: table list, primary keys, FK order and sequences all come
-- from pg_catalog. The only configuration is the two arguments of the
-- functions below (excluded tables, secret columns).
--
--   mirror.stage_plan()  -> what to pull: one row per mirrored table + its column list
--   mirror.prepare_staging()  -> (re)creates empty staging tables mirror_stg.<t>
--   (caller COPYs prod rows into mirror_stg.<t>)
--   mirror.run()         -> guards, upsert (parents first), delete-missing (children first),
--                           sequence reset; returns per-table counts. One transaction:
--                           any error rolls the whole run back.

create schema if not exists mirror;
create schema if not exists mirror_stg;

-- Tables that exist in the target but not in the source (structure drift, e.g. dev-only
-- lookup tables). pull() refreshes this every run; they are left untouched by run().
create table if not exists mirror.skipped (tbl text primary key);

-- Tables in FK dependency order (parents first). Self-references are ignored;
-- FKs to tables outside the set (e.g. studio.fsma_classifications) are ignored.
create or replace function mirror.table_order(
    p_schema   text   default 'whatsfresh',
    p_excluded text[] default array['context_store']
) returns table (lvl int, tbl text)
language plpgsql as $$
declare
    n_left int;
begin
    create temp table if not exists _mo_t (tbl text primary key, lvl int) on commit drop;
    create temp table if not exists _mo_d (child text, parent text) on commit drop;
    truncate _mo_t, _mo_d;

    insert into _mo_t (tbl)
    select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = p_schema and c.relkind = 'r' and c.relname <> all (p_excluded)
      and c.relname not in (select k.tbl from mirror.skipped k);

    insert into _mo_d
    select distinct cc.relname, pc.relname
    from pg_constraint k
    join pg_class cc on cc.oid = k.conrelid
    join pg_class pc on pc.oid = k.confrelid
    join pg_namespace cn on cn.oid = cc.relnamespace
    join pg_namespace pn on pn.oid = pc.relnamespace
    where k.contype = 'f' and cn.nspname = p_schema and pn.nspname = p_schema
      and cc.oid <> pc.oid
      and cc.relname in (select t.tbl from _mo_t t) and pc.relname in (select t.tbl from _mo_t t);

    for i in 0..50 loop
        update _mo_t t set lvl = i
        where t.lvl is null
          and not exists (select 1 from _mo_d d join _mo_t p on p.tbl = d.parent
                          where d.child = t.tbl and (p.lvl is null or p.lvl >= i));
        select count(*) into n_left from _mo_t t where t.lvl is null;
        exit when n_left = 0;
    end loop;
    if n_left > 0 then
        raise exception 'mirror.table_order: FK cycle among %',
            (select string_agg(t.tbl, ',') from _mo_t t where t.lvl is null);
    end if;
    return query select t.lvl, t.tbl from _mo_t t order by t.lvl, t.tbl;
end $$;

-- Secret columns are never pulled: staging leaves them NULL, insert uses an
-- unusable placeholder if the target column is NOT NULL, update leaves dev's value alone.
create or replace function mirror.secret_cols(p_table text) returns text[]
language sql immutable as $$
    select case p_table when 'users' then array['password','appsmith_pwd','remember_token']
                        else array[]::text[] end
$$;

create or replace function mirror.stage_plan(p_schema text default 'whatsfresh')
returns table (tbl text, cols text)
language sql as $$
    select o.tbl,
           (select string_agg(quote_ident(a.attname), ',' order by a.attnum)
            from pg_attribute a
            where a.attrelid = format('%I.%I', p_schema, o.tbl)::regclass
              and a.attnum > 0 and not a.attisdropped
              and a.attname <> all (mirror.secret_cols(o.tbl)))
    from mirror.table_order(p_schema) o order by o.lvl, o.tbl
$$;

create or replace function mirror.prepare_staging(p_schema text default 'whatsfresh')
returns int language plpgsql as $$
declare r record; n int := 0;
begin
    for r in select o.tbl from mirror.table_order(p_schema) o loop
        execute format('drop table if exists mirror_stg.%I', r.tbl);
        -- CTAS WITH NO DATA: columns only, no NOT NULL / defaults / constraints
        execute format('create table mirror_stg.%I as select * from %I.%I with no data',
                       r.tbl, p_schema, r.tbl);
        n := n + 1;
    end loop;
    return n;
end $$;

create or replace function mirror.run(
    p_schema    text    default 'whatsfresh',
    p_min_ratio numeric default 0.5     -- refuse if staged rows < ratio * target rows
) returns table (tbl text, source_rows bigint, inserted bigint, updated bigint, deleted bigint)
language plpgsql as $$
declare
    r record;
    s_cnt bigint; d_cnt bigint;
    pk text[]; allc text[]; updc text[]; secret text[];
    ins_list text; sel_list text; set_list text; old_list text; new_list text; on_list text; join_list text;
    v_ins bigint; v_upd bigint; v_del bigint;
    seq text;
begin
    create temp table _mirror_report (tbl text primary key, source_rows bigint, inserted bigint, updated bigint, deleted bigint) on commit drop;

    -- 1. Guards, before anything is changed
    for r in select o.tbl from mirror.table_order(p_schema) o loop
        if to_regclass(format('mirror_stg.%I', r.tbl)) is null then
            raise exception 'mirror: staging table for % missing (run prepare_staging + load)', r.tbl;
        end if;
        execute format('select count(*) from mirror_stg.%I', r.tbl) into s_cnt;
        execute format('select count(*) from %I.%I', p_schema, r.tbl) into d_cnt;
        if d_cnt > 0 and s_cnt = 0 then
            raise exception 'mirror guard: % staged 0 rows but target has % - refusing', r.tbl, d_cnt;
        end if;
        if d_cnt > 0 and s_cnt < d_cnt * p_min_ratio then
            raise exception 'mirror guard: % staged % rows vs % in target (< % ratio) - refusing',
                r.tbl, s_cnt, d_cnt, p_min_ratio;
        end if;
    end loop;

    -- 2. Upsert, parents first
    for r in select o.tbl from mirror.table_order(p_schema) o order by o.lvl, o.tbl loop
        select array_agg(a.attname order by a.attnum) into pk
        from pg_index i join pg_attribute a on a.attrelid = i.indrelid and a.attnum = any (i.indkey)
        where i.indrelid = format('%I.%I', p_schema, r.tbl)::regclass and i.indisprimary;
        if pk is null then raise exception 'mirror: % has no primary key', r.tbl; end if;

        secret := mirror.secret_cols(r.tbl);
        select array_agg(a.attname order by a.attnum) into allc
        from pg_attribute a where a.attrelid = format('%I.%I', p_schema, r.tbl)::regclass
          and a.attnum > 0 and not a.attisdropped;
        select array_agg(c) into updc from unnest(allc) c where c <> all (pk) and c <> all (secret);

        select string_agg(quote_ident(c), ',') into ins_list from unnest(allc) c;
        select string_agg(
                 case when c = any (secret) then
                      case when (select a.attnotnull from pg_attribute a
                                 where a.attrelid = format('%I.%I', p_schema, r.tbl)::regclass and a.attname = c)
                           then quote_literal('*') else 'null' end
                      else format('s.%I', c) end, ',') into sel_list from unnest(allc) c;
        select string_agg(quote_ident(c), ',') into on_list from unnest(pk) c;

        if updc is null then   -- table is only its key
            execute format('insert into %I.%I (%s) select %s from mirror_stg.%I s on conflict (%s) do nothing',
                           p_schema, r.tbl, ins_list, sel_list, r.tbl, on_list);
            v_ins := 0; v_upd := 0;
        else
            select string_agg(format('%I = excluded.%I', c, c), ', ') into set_list from unnest(updc) c;
            select string_agg(format('%I.%I', r.tbl, c), ',') into old_list from unnest(updc) c;
            select string_agg(format('excluded.%I', c), ',') into new_list from unnest(updc) c;
            execute format(
              'with up as (insert into %1$I.%2$I (%3$s) select %4$s from mirror_stg.%2$I s '
              ' on conflict (%5$s) do update set %6$s where (%7$s) is distinct from (%8$s) returning (xmax = 0) as ins) '
              'select count(*) filter (where ins), count(*) filter (where not ins) from up',
              p_schema, r.tbl, ins_list, sel_list, on_list, set_list, old_list, new_list)
              into v_ins, v_upd;
        end if;

        execute format('select count(*) from mirror_stg.%I', r.tbl) into s_cnt;
        insert into _mirror_report values (r.tbl, s_cnt, v_ins, v_upd, 0);
    end loop;

    -- 3. Delete-missing, children first
    for r in select o.tbl from mirror.table_order(p_schema) o order by o.lvl desc, o.tbl loop
        select array_agg(a.attname order by a.attnum) into pk
        from pg_index i join pg_attribute a on a.attrelid = i.indrelid and a.attnum = any (i.indkey)
        where i.indrelid = format('%I.%I', p_schema, r.tbl)::regclass and i.indisprimary;
        select string_agg(format('s.%I = x.%I', c, c), ' and ') into join_list from unnest(pk) c;
        execute format('with d as (delete from %I.%I x where not exists (select 1 from mirror_stg.%I s where %s) returning 1) select count(*) from d',
                       p_schema, r.tbl, r.tbl, join_list) into v_del;
        -- patch the row already emitted for this table
        update _mirror_report m set deleted = v_del where m.tbl = r.tbl;
    end loop;

    -- 4. Sequences: move past the highest mirrored id so a stray dev insert cannot collide
    for r in select o.tbl from mirror.table_order(p_schema) o loop
        for seq in select pg_get_serial_sequence(format('%I.%I', p_schema, r.tbl), a.attname)
                   from pg_attribute a where a.attrelid = format('%I.%I', p_schema, r.tbl)::regclass
                     and a.attnum > 0 and not a.attisdropped
                     and pg_get_serial_sequence(format('%I.%I', p_schema, r.tbl), a.attname) is not null
        loop
            execute format('select setval(%L, greatest((select coalesce(max(id),0) from %I.%I), 1))',
                           seq, p_schema, r.tbl);
        end loop;
    end loop;

    return query select m.tbl, m.source_rows, m.inserted, m.updated, m.deleted from _mirror_report m order by m.tbl;
end $$;

-- Stage prod rows over dblink (replaces mirror-pull.sh). Read-only on the source.
-- p_server is a dblink/FDW server name with a user mapping (dev: pg_prod_server).
create or replace function mirror.pull(
    p_schema text default 'whatsfresh',
    p_server text default 'pg_prod_server'
) returns table (tbl text, staged bigint)
language plpgsql as $$
declare
    r record; coldefs text; n bigint;
begin
    -- target tables the source does not have are skipped (and reported), not fatal
    truncate mirror.skipped;
    insert into mirror.skipped (tbl)
    select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = p_schema and c.relkind = 'r' and c.relname <> 'context_store'
      and not exists (select 1 from dblink(p_server,
              format('select table_name::text from information_schema.tables where table_schema = %L and table_type = ''BASE TABLE''', p_schema))
              as s(table_name text) where s.table_name = c.relname);
    for r in select k.tbl from mirror.skipped k order by 1 loop
        tbl := 'SKIPPED (not in source): ' || r.tbl; staged := null; return next;
    end loop;
    perform mirror.prepare_staging(p_schema);
    for r in select * from mirror.stage_plan(p_schema) loop
        select string_agg(format('%I %s', a.attname, format_type(a.atttypid, a.atttypmod)), ', ' order by a.attnum)
          into coldefs
        from pg_attribute a
        where a.attrelid = format('%I.%I', p_schema, r.tbl)::regclass
          and a.attnum > 0 and not a.attisdropped and a.attname <> all (mirror.secret_cols(r.tbl));
        execute format('insert into mirror_stg.%I (%s) select %s from dblink(%L, %L) as d(%s)',
                       r.tbl, r.cols, r.cols, p_server,
                       format('select %s from %I.%I', r.cols, p_schema, r.tbl), coldefs);
        get diagnostics n = row_count;
        tbl := r.tbl; staged := n; return next;
    end loop;
end $$;
