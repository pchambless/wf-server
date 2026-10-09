CREATE OR REPLACE FUNCTION deployment.f_start_run(p_pipeline text, p_env text, p_git_commit text DEFAULT NULL::text, p_by text DEFAULT 'deploy'::text, p_dry_run boolean DEFAULT false)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_release  integer;
  v_pipeline integer;
  v_env      integer;
  v_dep      integer;
  v_run      integer;
BEGIN
  -- Run lifecycle lives in the DB so bash (start_run.sh) and the n8n
  -- orchestrator open runs identically. p_pipeline 'all'/NULL/'' = holistic
  -- run (deployments.pipeline_id NULL = every leg); a pipeline name pins one leg.
  SELECT id INTO v_release FROM deployment.releases WHERE status = 'pending' ORDER BY id DESC LIMIT 1;
  IF v_release IS NULL THEN
    RAISE EXCEPTION 'f_start_run: no pending release - create one in deployment.releases first';
  END IF;

  SELECT id INTO v_env FROM deployment.environments WHERE name = p_env;
  IF v_env IS NULL THEN
    RAISE EXCEPTION 'f_start_run: unknown environment %', p_env;
  END IF;

  IF coalesce(p_pipeline, '') NOT IN ('', 'all') THEN
    SELECT id INTO v_pipeline FROM deployment.pipelines WHERE name = p_pipeline;
    IF v_pipeline IS NULL THEN
      RAISE EXCEPTION 'f_start_run: unknown pipeline %', p_pipeline;
    END IF;
  END IF;

  INSERT INTO deployment.deployments (environment_id, pipeline_id, release_id, git_commit, created_by)
  VALUES (v_env, v_pipeline, v_release, nullif(p_git_commit, ''), p_by)
  RETURNING id INTO v_dep;

  INSERT INTO deployment.deployment_runs (deployment_id, attempt, status, triggered_by, dry_run)
  VALUES (v_dep, 1, 'running', p_by, p_dry_run)
  RETURNING id INTO v_run;

  RETURN v_run;
END
$function$
;

