CREATE OR REPLACE FUNCTION deployment.f_finish_run(p_run_id integer, p_status text DEFAULT 'succeeded'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_violations text;
  v_actual     text;
BEGIN
  -- 'succeeded' is gated by f_check_run (the single rule set). Violations leave
  -- the run 'running' and are returned; any other status (e.g. 'aborted') skips
  -- the check. Never overwrites a failed run.
  IF p_status = 'succeeded' THEN
    SELECT string_agg(rule || ': ' || detail, E'\n') INTO v_violations FROM deployment.f_check_run(p_run_id);
    IF v_violations IS NOT NULL THEN
      RETURN jsonb_build_object('ok', false, 'run_id', p_run_id, 'status', 'running', 'violations', v_violations);
    END IF;
  END IF;

  UPDATE deployment.deployment_runs SET status = p_status, finished_at = now()
   WHERE id = p_run_id AND status <> 'failed';

  SELECT status INTO v_actual FROM deployment.deployment_runs WHERE id = p_run_id;
  RETURN jsonb_build_object('ok', v_actual = p_status, 'run_id', p_run_id, 'status', v_actual);
END
$function$
;

