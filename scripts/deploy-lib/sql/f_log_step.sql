CREATE OR REPLACE FUNCTION deployment.f_log_step(p_run_id integer, p_step text, p_status text, p_detail text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_id integer;
BEGIN
  -- The one place a deploy step event is recorded: bash (run_step.sh,
  -- deploy_step.sh) and the n8n orchestrator both call this, so the trajectory
  -- the monitor, f_check_run and deploy_eval read has a single writer.
  IF p_status NOT IN ('running', 'success', 'error') THEN
    RAISE EXCEPTION 'f_log_step: status must be running/success/error, got %', p_status;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM deployment.deployment_runs WHERE id = p_run_id) THEN
    RAISE EXCEPTION 'f_log_step: run % not found', p_run_id;
  END IF;

  -- ts = clock_timestamp(), not the column default now(): now() is the transaction
  -- start, so the running+success rows f_run_step writes in one call would tie and
  -- readers ordering by ts (monitor, deploy_trajectory) could pick the wrong one.
  INSERT INTO deployment.deployment_run_steps (run_id, step_name, status, detail, ts)
  VALUES (p_run_id, p_step, p_status, left(p_detail, 500), clock_timestamp())
  RETURNING id INTO v_id;

  -- An error ends the run (same contract run_step.sh had). error_stage is the
  -- coarse bucket constraint (connect/plan/execute/verify); step_name is the
  -- precise record. Never overwrites a run that already failed.
  IF p_status = 'error' THEN
    UPDATE deployment.deployment_runs
       SET status = 'failed', error = left(p_detail, 500), error_stage = 'execute', finished_at = now()
     WHERE id = p_run_id AND status <> 'failed';

    UPDATE agile.agile_cache a SET status = 'Blocked', updated_at = now(), updated_by = 'deploy'
      FROM deployment.deployment_runs r JOIN deployment.deployments d ON d.id = r.deployment_id
     WHERE r.id = p_run_id AND d.task_id = a.id AND NOT r.dry_run AND a.status = 'In Progress';
  END IF;

  RETURN v_id;
END
$function$
;

