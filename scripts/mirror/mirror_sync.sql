-- Prod -> dev nightly mirror of the whatsfresh schema (Task 609).
-- Catalog-driven: table list, primary keys, FK order and sequences all come
-- from pg_catalog. The only configuration is the two arguments of the
-- functions below (excluded tables, secret columns).
--
--   mirror.stage_plan()  -> what to pull: one row per mirrored table + its column list
--   mirror.prepare_staging()  -> (re)creates empty staging tables mirror_stg.<t>
--   (caller COPYs prod rows into mirror_stg.<t>)
--   mirror.run()         -> guards (tables of 100+ rows), clear secondary-unique-key conflicts, upsert (parents first,
--                           OVERRIDING SYSTEM VALUE for identity ids); before any delete or key change, every row
--                           pointing at the dev row goes first, any table (mirror.clear_refs): prod always wins,
--                           delete-missing (children first),
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

-- Rows created on the target (dev) can hold a secondary unique key (e.g. usi_lineage) that prod later
-- gave to a row with a different primary key. Inserting prod's row would then fail and roll the whole
-- run back. This deletes such target rows (prod's copy replaces them in the upsert). Catalog-driven:
-- every non-primary unique index, partial predicates and expression keys included. NULL keys never
-- match (same as the index). Returns rows deleted.
CREATE OR REPLACE FUNCTION mirror.clear_key_conflicts(p_schema text, p_tbl text)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
declare
    rel regclass := format('%I.%I', p_schema, p_tbl)::regclass;
    pk text[]; ix record;
    s_cols text; match text; pk_ne text; pred text;
    n bigint; total bigint := 0; doomed text;
begin
    select array_agg(a.attname order by a.attnum) into pk
    from pg_index i join pg_attribute a on a.attrelid = i.indrelid and a.attnum = any (i.indkey)
    where i.indrelid = rel and i.indisprimary;
    if pk is null then return 0; end if;

    for ix in
        select i.indexrelid, i.indnkeyatts, i.indkey, pg_get_expr(i.indpred, i.indrelid) as pred
        from pg_index i
        where i.indrelid = rel and i.indisunique and not i.indisprimary and i.indisvalid
          -- an index that contains the whole PK cannot collide under a different PK
          and not (select bool_and(a.attnum = any (i.indkey)) from pg_attribute a
                   where a.attrelid = rel and a.attname = any (pk))
    loop
        -- key k is a column name or an expression (unqualified); evaluated on staged and target rows
        select string_agg(format('%s as _k%s', pg_get_indexdef(ix.indexrelid, g, true), g), ', '),
               string_agg(format('s._k%s = (%s)', g, pg_get_indexdef(ix.indexrelid, g, true)), ' and ')
          into s_cols, match
          from generate_series(1, ix.indnkeyatts) g;
        select s_cols || ', ' || string_agg(format('%I as _p%s', c, o), ', '),
               '(' || string_agg(format('s._p%s', o), ',') || ') is distinct from ('
                   || string_agg(format('x.%I', c), ',') || ')'
          into s_cols, pk_ne
          from unnest(pk) with ordinality u(c, o);
        pred := coalesce(ix.pred, 'true');
        doomed := format(
            'select x.* from %1$I.%2$I x where (%3$s) and exists ('
            ' select 1 from (select %4$s from mirror_stg.%2$I where (%3$s)) s'
            ' where %5$s and (%6$s))',
            p_schema, p_tbl, pred, s_cols, match, pk_ne);
        -- Task 895: rows pointing at the dev row go first (any table); the upsert restores the ones prod has
        perform mirror.clear_refs(p_schema, p_tbl, doomed, 'key conflict');
        execute format(
            'with d as (delete from %1$I.%2$I x where (%3$s) and exists ('
            ' select 1 from (select %4$s from mirror_stg.%2$I where (%3$s)) s'
            ' where %5$s and (%6$s)) returning 1) select count(*) from d',
            p_schema, p_tbl, pred, s_cols, match, pk_ne) into n;
        total := total + n;
    end loop;
    return total;
end $function$
;

-- Task 895: the first clear_refs signature (p_mirrored text[]) lived on dev only briefly
DROP FUNCTION IF EXISTS mirror.clear_refs(text, text, text, text[], integer);

-- Task 895: prod always wins, dev data never fails the mirror. Before the mirror deletes a target row (delete-missing,
-- unique-key conflicts) or changes a key other rows point at (id collision), every row that references it is deleted
-- first, in any table and any schema, mirrored or not, recursively (grandchildren first). A deleted row that prod has
-- is put back by the upsert; one prod does not have is dev practice data and is meant to go. Catalog-driven from
-- pg_constraint. Assumes no FK cycles (mirror.table_order already refuses those inside the schema).
-- p_doomed: a query returning the p_tbl rows whose referencing rows must go (all columns).
-- Counts per table go to temp table _mirror_refs (tbl, phase, n).
CREATE OR REPLACE FUNCTION mirror.clear_refs(p_schema text, p_tbl text, p_doomed text, p_phase text DEFAULT 'refs', p_depth integer DEFAULT 0)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
declare
    k record; v bigint; total bigint := 0;
begin
    if p_depth > 20 then
        raise exception 'mirror.clear_refs: reference chain deeper than 20 at %.%', p_schema, p_tbl;
    end if;
    if to_regclass('pg_temp._mirror_refs') is null then
        create temp table _mirror_refs (tbl text, phase text, n bigint) on commit drop;
    end if;
    for k in
        select ns.nspname as cschema, c.relname as child,
               (select string_agg(format('c.%I', a.attname), ',' order by u.o)
                  from unnest(fk.conkey) with ordinality u(num, o)
                  join pg_attribute a on a.attrelid = fk.conrelid and a.attnum = u.num) as ccols,
               (select string_agg(format('d.%I', a.attname), ',' order by u.o)
                  from unnest(fk.confkey) with ordinality u(num, o)
                  join pg_attribute a on a.attrelid = fk.confrelid and a.attnum = u.num) as pcols
        from pg_constraint fk
        join pg_class c on c.oid = fk.conrelid
        join pg_namespace ns on ns.oid = c.relnamespace
        where fk.contype = 'f' and fk.confrelid = format('%I.%I', p_schema, p_tbl)::regclass
          and fk.conrelid <> fk.confrelid
        order by ns.nspname, c.relname
    loop
        total := total + mirror.clear_refs(k.cschema, k.child,
            format('select c.* from %I.%I c where (%s) in (select %s from (%s) d)',
                   k.cschema, k.child, k.ccols, k.pcols, p_doomed),
            p_phase, p_depth + 1);
        execute format('with x as (delete from %I.%I c where (%s) in (select %s from (%s) d) returning 1) select count(*) from x',
                       k.cschema, k.child, k.ccols, k.pcols, p_doomed) into v;
        if v > 0 then
            insert into _mirror_refs values (k.cschema || '.' || k.child, p_phase, v);
        end if;
        total := total + v;
    end loop;
    return total;
end $function$;

CREATE OR REPLACE FUNCTION mirror.run(p_schema text DEFAULT 'whatsfresh'::text, p_min_ratio numeric DEFAULT 0.5)
 RETURNS TABLE(tbl text, source_rows bigint, inserted bigint, updated bigint, deleted bigint)
 LANGUAGE plpgsql
AS $function$
declare
    r record;
    s_cnt bigint; d_cnt bigint;
    pk text[]; allc text[]; updc text[]; secret text[];
    ins_list text; sel_list text; set_list text; old_list text; new_list text; on_list text; join_list text;
    v_ins bigint; v_upd bigint; v_del bigint;
    seq record; ovr text; fkc record;
    -- Task 895: tables this small skip the ratio guards; a new prod table (Release 28: shipments, recalls,
    -- location_sources) starts empty while dev still holds test rows. A broken pull still trips the big tables.
    c_guard_min constant bigint := 100;
begin
    -- Task 877: whatsfresh triggers that judge new data (e.g. duplicate batch numbers) skip copies of rows prod already accepted.
    perform set_config('whatsfresh.copying_prod', 'on', true);
    create temp table _mirror_report (tbl text primary key, source_rows bigint, inserted bigint, updated bigint, deleted bigint) on commit drop;
    if to_regclass('pg_temp._mirror_refs') is null then
        create temp table _mirror_refs (tbl text, phase text, n bigint) on commit drop;
    end if;

    -- 1. Guards, before anything is changed
    for r in select o.tbl from mirror.table_order(p_schema) o loop
        if to_regclass(format('mirror_stg.%I', r.tbl)) is null then
            raise exception 'mirror: staging table for % missing (run prepare_staging + load)', r.tbl;
        end if;
        execute format('select count(*) from mirror_stg.%I', r.tbl) into s_cnt;
        execute format('select count(*) from %I.%I', p_schema, r.tbl) into d_cnt;
        if d_cnt >= c_guard_min and s_cnt = 0 then
            raise exception 'mirror guard: % staged 0 rows but target has % - refusing', r.tbl, d_cnt;
        end if;
        if d_cnt >= c_guard_min and s_cnt < d_cnt * p_min_ratio then
            raise exception 'mirror guard: % staged % rows vs % in target (< % ratio) - refusing',
                r.tbl, s_cnt, d_cnt, p_min_ratio;
        end if;
    end loop;

    -- 1b. Secondary unique keys: delete target rows whose unique key (e.g. usi_lineage) belongs to a
    --     staged row with a different PK, children first, so the upsert cannot collide. Counted as deleted.
    create temp table _mirror_cleared (tbl text primary key, n bigint) on commit drop;
    for r in select o.tbl from mirror.table_order(p_schema) o order by o.lvl desc, o.tbl loop
        insert into _mirror_cleared values (r.tbl, mirror.clear_key_conflicts(p_schema, r.tbl));
    end loop;

    -- 1c. Task 895, id collisions: where a dev row and prod's row share a PK but differ in columns another table
    --     references (e.g. entities.entity_kind, ON UPDATE RESTRICT), the upsert would break those references.
    --     Rows pointing at such dev rows go first; the upsert restores the ones prod has.
    for r in select o.tbl from mirror.table_order(p_schema) o order by o.lvl desc, o.tbl loop
        select array_agg(a.attname order by a.attnum) into pk
        from pg_index i join pg_attribute a on a.attrelid = i.indrelid and a.attnum = any (i.indkey)
        where i.indrelid = format('%I.%I', p_schema, r.tbl)::regclass and i.indisprimary;
        select string_agg(format('s.%I = x.%I', c, c), ' and ') into join_list from unnest(pk) c;
        for fkc in
            select distinct
                   (select string_agg(format('x.%I', a.attname), ',' order by a.attnum) from pg_attribute a
                     where a.attrelid = fk.confrelid and a.attnum = any (fk.confkey)) as xcols,
                   (select string_agg(format('s.%I', a.attname), ',' order by a.attnum) from pg_attribute a
                     where a.attrelid = fk.confrelid and a.attnum = any (fk.confkey)) as scols
            from pg_constraint fk
            where fk.contype = 'f' and fk.confrelid = format('%I.%I', p_schema, r.tbl)::regclass
              and exists (select 1 from pg_attribute a where a.attrelid = fk.confrelid
                          and a.attnum = any (fk.confkey) and a.attname <> all (pk))
        loop
            perform mirror.clear_refs(p_schema, r.tbl,
                format('select x.* from %I.%I x join mirror_stg.%I s on %s where row(%s) is distinct from row(%s)',
                       p_schema, r.tbl, r.tbl, join_list, fkc.xcols, fkc.scols), 'key change');
        end loop;
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
        -- Task 895: GENERATED ALWAYS identity columns (Release 28 tables) refuse prod's ids without OVERRIDING SYSTEM VALUE
        select case when exists (select 1 from pg_attribute a where a.attrelid = format('%I.%I', p_schema, r.tbl)::regclass
                                   and a.attnum > 0 and not a.attisdropped and a.attidentity = 'a')
                    then ' overriding system value' else '' end into ovr;

        if updc is null then   -- table is only its key
            execute format('insert into %I.%I (%s)%s select %s from mirror_stg.%I s on conflict (%s) do nothing',
                           p_schema, r.tbl, ins_list, ovr, sel_list, r.tbl, on_list);
            v_ins := 0; v_upd := 0;
        else
            select string_agg(format('%I = excluded.%I', c, c), ', ') into set_list from unnest(updc) c;
            select string_agg(format('%I.%I', r.tbl, c), ',') into old_list from unnest(updc) c;
            select string_agg(format('excluded.%I', c), ',') into new_list from unnest(updc) c;
            execute format(
              'with up as (insert into %1$I.%2$I (%3$s)%9$s select %4$s from mirror_stg.%2$I s '
              ' on conflict (%5$s) do update set %6$s where (%7$s) is distinct from (%8$s) returning (xmax = 0) as ins) '
              'select count(*) filter (where ins), count(*) filter (where not ins) from up',
              p_schema, r.tbl, ins_list, sel_list, on_list, set_list, old_list, new_list, ovr)
              into v_ins, v_upd;
        end if;

        execute format('select count(*) from mirror_stg.%I', r.tbl) into s_cnt;
        insert into _mirror_report values (r.tbl, s_cnt, v_ins, v_upd, 0);
    end loop;

    -- 3. Delete-missing, children first. Task 895: rows in any other table (dev-only tables, other schemas) that
    --    reference a doomed row are deleted first (mirror.clear_refs).
    for r in select o.tbl from mirror.table_order(p_schema) o order by o.lvl desc, o.tbl loop
        select array_agg(a.attname order by a.attnum) into pk
        from pg_index i join pg_attribute a on a.attrelid = i.indrelid and a.attnum = any (i.indkey)
        where i.indrelid = format('%I.%I', p_schema, r.tbl)::regclass and i.indisprimary;
        select string_agg(format('s.%I = x.%I', c, c), ' and ') into join_list from unnest(pk) c;
        perform mirror.clear_refs(p_schema, r.tbl,
            format('select x.* from %I.%I x where not exists (select 1 from mirror_stg.%I s where %s)',
                   p_schema, r.tbl, r.tbl, join_list), 'delete-missing');
        execute format('with d as (delete from %I.%I x where not exists (select 1 from mirror_stg.%I s where %s) returning 1) select count(*) from d',
                       p_schema, r.tbl, r.tbl, join_list) into v_del;
        -- patch the row already emitted for this table
        update _mirror_report m set deleted = v_del + coalesce((select c.n from _mirror_cleared c where c.tbl = r.tbl), 0)
         where m.tbl = r.tbl;
    end loop;

    -- 4. Sequences: move past the highest mirrored id so a stray dev insert cannot collide
    for r in select o.tbl from mirror.table_order(p_schema) o loop
        for seq in select a.attname, pg_get_serial_sequence(format('%I.%I', p_schema, r.tbl), a.attname) as s
                   from pg_attribute a where a.attrelid = format('%I.%I', p_schema, r.tbl)::regclass
                     and a.attnum > 0 and not a.attisdropped
                     and pg_get_serial_sequence(format('%I.%I', p_schema, r.tbl), a.attname) is not null
        loop
            execute format('select setval(%L, greatest((select coalesce(max(%I),0) from %I.%I), 1))',
                           seq.s, seq.attname, p_schema, r.tbl);
        end loop;
    end loop;

    -- Task 895: rows cleared because they referenced dev data (a mirrored table's row may be restored by the upsert)
    insert into _mirror_report
    select format('refs cleared (%s): %s', f.phase, f.tbl), null, 0, 0, sum(f.n) from _mirror_refs f group by f.phase, f.tbl;

    return query select m.tbl, m.source_rows, m.inserted, m.updated, m.deleted from _mirror_report m order by m.tbl;
end $function$
;

-- Stage prod rows over dblink (replaces mirror-pull.sh). Read-only on the source.
-- p_server is a dblink/FDW server name with a user mapping (dev: pg_prod_server).
CREATE OR REPLACE FUNCTION mirror.pull(p_schema text DEFAULT 'whatsfresh'::text, p_server text DEFAULT 'pg_prod_server'::text)
 RETURNS TABLE(tbl text, staged bigint)
 LANGUAGE plpgsql
AS $function$
declare
    r record; coldefs text; cols text; n bigint;
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

    -- Columns the source has, per table. A column added on dev before it ships (Task 883: locations.address) is
    -- not on prod yet: it is left out of the pull and stays NULL in staging instead of failing the whole run.
    create temp table _src_cols on commit drop as
    select s.table_name, s.column_name
      from dblink(p_server,
             format('select table_name::text, column_name::text from information_schema.columns where table_schema = %L', p_schema))
           as s(table_name text, column_name text);

    perform mirror.prepare_staging(p_schema);
    for r in select * from mirror.stage_plan(p_schema) loop
        select string_agg(quote_ident(a.attname), ',' order by a.attnum),
               string_agg(format('%I %s', a.attname, format_type(a.atttypid, a.atttypmod)), ', ' order by a.attnum)
          into cols, coldefs
        from pg_attribute a
        where a.attrelid = format('%I.%I', p_schema, r.tbl)::regclass
          and a.attnum > 0 and not a.attisdropped and a.attname <> all (mirror.secret_cols(r.tbl))
          and exists (select 1 from _src_cols sc where sc.table_name = r.tbl and sc.column_name = a.attname);
        if cols is distinct from r.cols then
            tbl := 'DEV-ONLY COLUMNS left NULL: ' || r.tbl; staged := null; return next;
        end if;
        execute format('insert into mirror_stg.%I (%s) select %s from dblink(%L, %L) as d(%s)',
                       r.tbl, cols, cols, p_server,
                       format('select %s from %I.%I', cols, p_schema, r.tbl), coldefs);
        get diagnostics n = row_count;
        tbl := r.tbl; staged := n; return next;
    end loop;
end $function$;
