CREATE OR REPLACE FUNCTION deployment.f_start_run(p_pipeline text, p_env text, p_git_commit text DEFAULT NULL::text, p_by text DEFAULT 'deploy'::text, p_dry_run boolean DEFAULT false, p_task_id integer DEFAULT NULL::integer, p_summary text DEFAULT NULL::text, p_sprint text DEFAULT NULL::text, p_release_id integer DEFAULT NULL::integer)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_release   integer;
  v_pipeline  integer;
  v_env       integer;
  v_is_target boolean;
  v_platform  text;
  v_task      integer;
  v_dep       integer;
  v_run       integer;
  v_scope     text;
BEGIN
  -- Run lifecycle lives in the DB so bash (start_run.sh) and the n8n
  -- orchestrator open runs identically. p_pipeline 'all'/NULL/'' = holistic
  -- run (deployments.pipeline_id NULL = every leg); a pipeline name pins one leg.
  -- The release a run belongs to (task 689): the one passed in (a hotfix), else the earliest unshipped dated release.
  v_release := coalesce(p_release_id, deployment.f_open_release_id());
  IF v_release IS NULL THEN
    RAISE EXCEPTION 'f_start_run: no open release - create one on the Releases page first';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM agile.releases r WHERE r.id = v_release AND r.deleted_at IS NULL AND r.kind <> 'backlog') THEN
    RAISE EXCEPTION 'f_start_run: release % does not exist or is the Backlog', v_release;
  END IF;

  SELECT id, is_target INTO v_env, v_is_target FROM deployment.environments WHERE name = p_env;
  IF v_env IS NULL THEN
    RAISE EXCEPTION 'f_start_run: unknown environment %', p_env;
  END IF;

  IF coalesce(p_pipeline, '') NOT IN ('', 'all') THEN
    SELECT id, platform INTO v_pipeline, v_platform FROM deployment.pipelines WHERE name = p_pipeline;
    IF v_pipeline IS NULL THEN
      RAISE EXCEPTION 'f_start_run: unknown pipeline %', p_pipeline;
    END IF;
  END IF;

  -- Only code-only runs (the wf-server pipeline) may target a non-deploy-target
  -- environment such as dev. A holistic run or a database/n8n pipeline there is
  -- refused up front, not three steps in (task 517: run 77 wiped dev's studio data).
  IF NOT v_is_target AND (v_pipeline IS NULL OR v_platform <> 'wf-server') THEN
    RAISE EXCEPTION 'f_start_run: environment % is not a deploy target - only the wf-server (code) pipeline may run there, not % ', p_env, coalesce(nullif(p_pipeline, ''), 'all');
  END IF;

  -- A live run on a deploy target is a release: tie it to a task (given, or a new
  -- release task filed now). Dry runs and dev code runs carry none.
  v_task := p_task_id;
  IF v_task IS NULL AND NOT p_dry_run AND v_is_target THEN
    -- single-leg run: say so in the release task title (task 562); holistic run: plain title
    -- label comes from the pipeline row (deployment.pipelines.scope_label); a pipeline without one
    -- falls back to its name; holistic run (no pipeline row) leaves it NULL = plain title
    SELECT coalesce(scope_label, name || ' only') INTO v_scope FROM deployment.pipelines WHERE id = v_pipeline;
    v_task := deployment.f_open_release_task(p_env, p_summary, p_sprint, p_by, v_scope);
  END IF;

  INSERT INTO deployment.deployments (environment_id, pipeline_id, release_id, git_commit, created_by, task_id)
  VALUES (v_env, v_pipeline, v_release, nullif(p_git_commit, ''), p_by, v_task)
  RETURNING id INTO v_dep;

  INSERT INTO deployment.deployment_runs (deployment_id, attempt, status, triggered_by, dry_run)
  VALUES (v_dep, 1, 'running', p_by, p_dry_run)
  RETURNING id INTO v_run;

  RETURN v_run;
END
$function$
;

