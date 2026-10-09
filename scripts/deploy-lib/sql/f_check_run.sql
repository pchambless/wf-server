CREATE OR REPLACE FUNCTION deployment.f_check_run(p_run_id integer)
 RETURNS TABLE(rule text, detail text)
 LANGUAGE sql
 STABLE
AS $function$
  -- One source of truth for "was this a valid deploy run?". Violations only;
  -- zero rows = clean. Called by finish_run.sh, the n8n orchestrator and the
  -- monitor; deploy_eval.py checks the same rules from Python.
  WITH r AS (
    SELECT r.id, d.pipeline_id
      FROM deployment.deployment_runs r
      JOIN deployment.deployments d ON d.id = r.deployment_id
     WHERE r.id = p_run_id
  ),
  first_ok AS (   -- first success per step
    SELECT step_name, min(ts) AS ts
      FROM deployment.deployment_run_steps
     WHERE run_id = p_run_id AND status = 'success'
     GROUP BY step_name
  )
  -- COMPLETE: a holistic run (pipeline_id NULL = all legs) needs every enabled step
  SELECT 'COMPLETE'::text,
         'no success logged for: ' || string_agg(ds.step_key, ', ' ORDER BY ds.ordr)
    FROM r
    JOIN deployment.deploy_steps ds ON ds.enabled
   WHERE r.pipeline_id IS NULL
     AND NOT EXISTS (SELECT 1 FROM first_ok f WHERE f.step_name = ds.step_key)
  HAVING count(*) > 0
  UNION ALL
  -- DATA_BEFORE_CODE: routes load at boot, so a code restart before the data step leaves stale routes (task 437)
  SELECT 'DATA_BEFORE_CODE'::text, 'deploy_code succeeded before data'
    FROM first_ok c JOIN first_ok d ON d.step_name = 'data'
   WHERE c.step_name = 'deploy_code' AND c.ts < d.ts
  UNION ALL
  -- GATES_FIRST: a mutating step succeeded before the gating checks did. The gating checks are derived
  -- from the catalog (enabled kind='check' steps ordered before 'structure'), not named here.
  SELECT 'GATES_FIRST'::text,
         m.step_name || ' succeeded before gate ' || g.step_name
    FROM first_ok m
    JOIN first_ok g ON g.step_name IN (SELECT step_key FROM deployment.deploy_steps
                                       WHERE enabled AND kind = 'check'
                                         AND ordr < (SELECT ordr FROM deployment.deploy_steps WHERE step_key = 'structure'))
   WHERE m.step_name IN ('structure', 'data', 'deploy_n8n', 'deploy_code')
     AND m.ts < g.ts
$function$
;

