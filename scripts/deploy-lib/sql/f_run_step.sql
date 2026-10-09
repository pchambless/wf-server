CREATE OR REPLACE FUNCTION deployment.f_run_step(p_run_id integer, p_step text, p_params jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_sql    text;
  v_key    text;
  v_val    text;
  v_rows   jsonb;
  v_detail text;
BEGIN
  -- Run one SQL deploy step end to end: look up deploy_steps.runs, substitute
  -- the :tokens from p_params as quoted literals, execute, and record
  -- running/success/error through f_log_step. Returns {ok, step, rows|error}
  -- and never raises for a step failure (the caller - bash or the n8n
  -- orchestrator - branches on ok). Bash steps (runs IS NULL) are not run here.
  SELECT runs INTO v_sql FROM deployment.deploy_steps WHERE step_key = p_step;
  IF NOT FOUND OR v_sql IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'step', p_step, 'error', 'no runs SQL for step (bash step or unknown key)');
  END IF;

  PERFORM deployment.f_log_step(p_run_id, p_step, 'running');

  BEGIN
    FOR v_key, v_val IN SELECT key, value FROM jsonb_each_text(p_params) LOOP
      -- (?<!:) so a ::cast is never mistaken for a :token; \M = end of word
      v_sql := regexp_replace(v_sql, '(?<!:):' || v_key || '\M', quote_literal(v_val), 'g');
    END LOOP;

    EXECUTE 'SELECT coalesce(jsonb_agg(to_jsonb(t)), ''[]''::jsonb) FROM (' || v_sql || ') t' INTO v_rows;

    v_detail := left(coalesce(v_rows -> 0, '{}'::jsonb)::text, 500);
    PERFORM deployment.f_log_step(p_run_id, p_step, 'success', v_detail);
    RETURN jsonb_build_object('ok', true, 'step', p_step, 'rows', v_rows);
  EXCEPTION WHEN OTHERS THEN
    PERFORM deployment.f_log_step(p_run_id, p_step, 'error', SQLERRM);
    RETURN jsonb_build_object('ok', false, 'step', p_step, 'error', SQLERRM);
  END;
END
$function$
;

