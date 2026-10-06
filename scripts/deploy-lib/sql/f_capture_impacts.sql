CREATE OR REPLACE FUNCTION deployment.f_capture_impacts(p_task_id integer, p_dry_run boolean DEFAULT true, p_by text DEFAULT 'drift-detector'::text)
 RETURNS TABLE(item_type text, schema_name text, object_name text, component_name text, status text, description text, written boolean)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_rows int;
BEGIN
    -- Scan first, unconditionally (even under dry_run - a preview should reflect
    -- current reality, not whatever the last scan happened to see). Without this,
    -- capture reads stale object_state and f_reconcile()'s own internal f_scan()
    -- (which runs AFTER capture, inside the non-dry-run branch below) would
    -- silently absorb any not-yet-scanned change into the baseline without ever
    -- having captured it as an impact - found live 2026-08-26 when object_state
    -- turned out to be a week stale and a real column addition
    -- (whatsfresh.batches.available) would have vanished into the baseline the
    -- next time this ran, unlogged.
    PERFORM deployment.f_scan();

    -- ORDER MATTERS AND IS NOT RECOVERABLE. Impacts are written from drift, and
    -- drift is defined against the baseline. Reconcile first and the changes are
    -- gone with nothing recording them. So: scan, capture, THEN advance.
    CREATE TEMP TABLE _cap ON COMMIT DROP AS
    SELECT CASE d.kind WHEN 'table'    THEN 'db_table'
                       WHEN 'view'     THEN 'db_view'
                       WHEN 'function' THEN 'db_function'
                       WHEN 'row'      THEN 'row'
                       WHEN 'workflow' THEN 'n8n_workflow'
                       WHEN 'node'     THEN 'n8n_node' END::text        AS item_type,
           d.schema_name::text,
           d.object_name::text,
           COALESCE(d.component_name, '')::text                      AS component_name,
           CASE d.change_type WHEN 'added'    THEN 'A'
                              WHEN 'modified' THEN 'M'
                              WHEN 'deleted'  THEN 'D' END::text      AS status,
           left(d.detail, 256)::text                                  AS description
      FROM deployment.vw_object_drift d
     -- Deployment scope only. object_state never holds anything else, but state the
     -- boundary explicitly so widening f_scan's schemas cannot silently widen this.
     -- 'n8n' added 2026-08-19 alongside kind IN ('workflow','node') - task 270/274.
     WHERE d.schema_name IN ('studio','whatsfresh','n8n');

    IF NOT p_dry_run THEN
        INSERT INTO agile.agile_impacts
               (task_id, item_type, schema_name, object_name, component_name, status, description, created_by)
        SELECT p_task_id, c.item_type, c.schema_name, c.object_name,
               NULLIF(c.component_name, ''), c.status, c.description, p_by
          FROM _cap c;
        GET DIAGNOSTICS v_rows = ROW_COUNT;
        RAISE NOTICE 'f_capture_impacts: wrote % impacts for task %', v_rows, p_task_id;

        PERFORM deployment.f_reconcile(p_by);
    END IF;

    RETURN QUERY
    SELECT c.item_type, c.schema_name, c.object_name, c.component_name,
           c.status, c.description, NOT p_dry_run
      FROM _cap c
     ORDER BY c.schema_name, c.object_name, c.component_name;
END;
$function$
;

