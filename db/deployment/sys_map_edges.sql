-- System map, DB layer, part 2: edges between live db nodes into deployment.sys_edge.
-- Sources: pg_depend (views, BEGIN ATOMIC sql functions), pg_constraint (FKs),
-- pg_trigger, and a regex scan of function bodies for schema-qualified names
-- (prosrc_scan). The scan misses unqualified names and dynamic SQL (format %I).
CREATE OR REPLACE FUNCTION deployment.f_sys_refresh_db_edges() RETURNS int LANGUAGE plpgsql AS $body$
DECLARE v_n int;
BEGIN
  CREATE TEMP TABLE _n ON COMMIT DROP AS
  SELECT id, kind, scope, name, attrs->>'proname' AS proname, (attrs->>'oid')::oid AS oid,
         CASE WHEN kind IN ('function','procedure') THEN 'pg_proc'::regclass::oid
              WHEN kind = 'trigger' THEN 'pg_trigger'::regclass::oid
              ELSE 'pg_class'::regclass::oid END AS classid
    FROM deployment.sys_node WHERE layer = 'db' AND deleted_at IS NULL;

  CREATE TEMP TABLE _e (from_id int, to_id int, kind text, attrs jsonb, source text) ON COMMIT DROP;

  -- views/matviews -> relations and functions they use
  INSERT INTO _e
  SELECT DISTINCT f.id, t.id, CASE WHEN t.classid = 'pg_proc'::regclass THEN 'calls' ELSE 'reads' END,
         '{}'::jsonb, 'pg_depend'
    FROM pg_depend d JOIN pg_rewrite r ON r.oid = d.objid AND d.classid = 'pg_rewrite'::regclass
    JOIN _n f ON f.oid = r.ev_class AND f.classid = 'pg_class'::regclass
    JOIN _n t ON t.oid = d.refobjid AND t.classid = d.refclassid
   WHERE f.id <> t.id;

  -- sql functions with BEGIN ATOMIC bodies record their deps
  INSERT INTO _e
  SELECT DISTINCT f.id, t.id, CASE WHEN t.classid = 'pg_proc'::regclass THEN 'calls' ELSE 'reads' END,
         '{}'::jsonb, 'pg_depend'
    FROM pg_depend d
    JOIN _n f ON f.oid = d.objid AND f.classid = 'pg_proc'::regclass AND d.classid = 'pg_proc'::regclass
    JOIN _n t ON t.oid = d.refobjid AND t.classid = d.refclassid AND t.kind NOT IN ('trigger')
   WHERE d.deptype = 'n' AND f.id <> t.id;

  -- foreign keys: child table references parent table
  INSERT INTO _e
  SELECT f.id, t.id, 'references', jsonb_build_object('constraint', k.conname), 'pg_constraint'
    FROM pg_constraint k
    JOIN _n f ON f.oid = k.conrelid AND f.classid = 'pg_class'::regclass
    JOIN _n t ON t.oid = k.confrelid AND t.classid = 'pg_class'::regclass
   WHERE k.contype = 'f' AND f.id <> t.id;

  -- triggers: fires_on its table, calls its function
  INSERT INTO _e
  SELECT tr.id, rel.id, 'fires_on', '{}'::jsonb, 'pg_trigger'
    FROM pg_trigger t JOIN _n tr ON tr.oid = t.oid AND tr.classid = 'pg_trigger'::regclass
    JOIN _n rel ON rel.oid = t.tgrelid AND rel.classid = 'pg_class'::regclass
  UNION ALL
  SELECT tr.id, fn.id, 'calls', '{}'::jsonb, 'pg_trigger'
    FROM pg_trigger t JOIN _n tr ON tr.oid = t.oid AND tr.classid = 'pg_trigger'::regclass
    JOIN _n fn ON fn.oid = t.tgfoid AND fn.classid = 'pg_proc'::regclass;

  -- function bodies: schema.name tokens, plus write verbs in front of them
  CREATE TEMP TABLE _refs ON COMMIT DROP AS
  SELECT f.id, r.scope, r.obj, r.verb
    FROM _n f JOIN pg_proc p ON p.oid = f.oid, deployment.f_sys_sql_refs(p.prosrc) r
   WHERE f.classid = 'pg_proc'::regclass
     AND p.prolang NOT IN (SELECT oid FROM pg_language WHERE lanname IN ('c','internal'));

  INSERT INTO _e
  SELECT DISTINCT r.id, t.id, 'writes', '{}'::jsonb, 'prosrc_scan'
    FROM _refs r JOIN _n t ON t.scope = r.scope AND t.name = r.obj AND t.kind IN ('table','view','matview')
   WHERE r.verb = 'writes' AND r.id <> t.id;

  INSERT INTO _e
  SELECT DISTINCT r.id, t.id,
         CASE WHEN t.kind IN ('function','procedure') THEN 'calls' ELSE 'reads' END, '{}'::jsonb, 'prosrc_scan'
    FROM _refs r JOIN _n t ON t.scope = r.scope
             AND (t.name = r.obj AND t.kind IN ('table','view','matview')
                  OR t.proname = r.obj AND t.kind IN ('function','procedure'))
   WHERE r.verb = 'ref' AND r.id <> t.id
     AND NOT EXISTS (SELECT 1 FROM _e w WHERE w.from_id = r.id AND w.to_id = t.id AND w.kind = 'writes');

  WITH agg AS (
    SELECT from_id, to_id, kind, min(source) AS source,
           CASE WHEN bool_or(attrs <> '{}') THEN jsonb_build_object('detail', jsonb_agg(DISTINCT attrs) FILTER (WHERE attrs <> '{}'))
                ELSE '{}'::jsonb END AS attrs
      FROM _e GROUP BY 1, 2, 3
  ), up AS (
    INSERT INTO deployment.sys_edge AS s (from_node_id, to_node_id, kind, attrs, source)
    SELECT from_id, to_id, kind, attrs, source FROM agg
    ON CONFLICT (from_node_id, to_node_id, kind) DO UPDATE
       SET attrs = EXCLUDED.attrs, source = EXCLUDED.source, last_seen = now(), deleted_at = NULL,
           updated_at = CASE WHEN s.attrs IS DISTINCT FROM EXCLUDED.attrs OR s.deleted_at IS NOT NULL
                             THEN now() ELSE s.updated_at END,
           updated_by = CASE WHEN s.attrs IS DISTINCT FROM EXCLUDED.attrs OR s.deleted_at IS NOT NULL
                             THEN 'f_sys_refresh_db' ELSE s.updated_by END
    RETURNING 1
  )
  SELECT count(*) INTO v_n FROM up;

  -- retire db-sourced edges not seen this run, and any edge touching a retired node
  UPDATE deployment.sys_edge e SET deleted_at = now(), updated_at = now(), updated_by = 'f_sys_refresh_db'
   WHERE e.deleted_at IS NULL
     AND ((e.source IN ('pg_depend','pg_constraint','pg_trigger','prosrc_scan') AND e.last_seen < now())
          OR EXISTS (SELECT 1 FROM deployment.sys_node n
                      WHERE n.id IN (e.from_node_id, e.to_node_id) AND n.deleted_at IS NOT NULL));
  RETURN v_n;
END
$body$;
