CREATE OR REPLACE FUNCTION deployment.f_mark_run_tasks(p_run_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_env     text;
  v_dry     boolean;
  v_release integer;
  v_task    integer;
  v_own     integer := 0;
  v_mapped  integer := 0;
BEGIN
  -- Records what a SUCCEEDED run shipped on the board (task 763, sprint 761).
  -- Dry runs change nothing. A prod run sets status Deployed on (1) the run's own
  -- task and (2) every Done task mapped to the run's release (agile.release_tasks,
  -- backlog excluded). No date fallback: a task is Deployed only because a run
  -- carried it. A non-prod run keeps the old behavior: its own task becomes Done.
  -- Deployed is never downgraded.
  SELECT e.name, r.dry_run, d.release_id, d.task_id
    INTO v_env, v_dry, v_release, v_task
    FROM deployment.deployment_runs r
    JOIN deployment.deployments d ON d.id = r.deployment_id
    JOIN deployment.environments e ON e.id = d.environment_id
   WHERE r.id = p_run_id;

  IF NOT FOUND OR v_dry THEN
    RETURN jsonb_build_object('own', 0, 'mapped', 0);
  END IF;

  IF v_task IS NOT NULL THEN
    UPDATE agile.agile_cache
       SET status = CASE WHEN v_env = 'prod' THEN 'Deployed' ELSE 'Done' END,
           updated_at = now(), updated_by = 'deploy'
     WHERE id = v_task
       AND status <> CASE WHEN v_env = 'prod' THEN 'Deployed' ELSE 'Done' END
       AND status <> 'Deployed';
    GET DIAGNOSTICS v_own = ROW_COUNT;
  END IF;

  IF v_env = 'prod' AND v_release IS NOT NULL THEN
    UPDATE agile.agile_cache a
       SET status = 'Deployed', updated_at = now(), updated_by = 'deploy'
      FROM agile.release_tasks rt
      JOIN agile.releases rl ON rl.id = rt.release_id AND rl.kind <> 'backlog' AND rl.deleted_at IS NULL
     WHERE rt.release_id = v_release AND rt.task_id = a.id
       AND a.page_type = 'Task' AND a.status = 'Done' AND a.deleted_at IS NULL;
    GET DIAGNOSTICS v_mapped = ROW_COUNT;
  END IF;

  RETURN jsonb_build_object('own', v_own, 'mapped', v_mapped);
END
$function$;
