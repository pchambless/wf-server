-- ============================================================================
-- Migration: f_p01_plan becomes run-id-first
-- Task:  agile_cache 505 (Sprint 504, Epic 401 Deployment Process)
-- Date:  2026-10-05  Author: claude (drafted)
--
-- WHY (run-id-first, Paul 2026-10-05):
--   The OLD f_p01_plan(text env, ...) creates BOTH a deployments row and a
--   deployment_runs row, so no run_id exists until step 50 - and the check
--   steps (compare/sequences) cannot log to deployment_run_steps (run_id NOT
--   NULL). The bash legs bypass it via start_run.sh because the OLD function
--   RAISES on zero planned objects (code is not a DB object).
--   Fix: start_run.sh becomes the single step-0 run creator for every leg;
--   f_p01_plan accepts that run_id and PLANS INTO it, creating nothing.
--
-- SHAPE:
--   - NEW overload f_p01_plan(p_run_id integer, p_pipeline text DEFAULT NULL).
--     Different arg types from the old one, so this is an additive overload -
--     old function stays callable until a practice deploy proves the new path,
--     then the old one is dropped (see CUTOVER).
--   - p_pipeline NULL = derive the pipeline from the run's own deployment, so
--     the planner filter can't drift from what start_run recorded.
--   - Zero planned objects is NO LONGER fatal (a wf-server/n8n leg plans zero
--     DB objects legitimately). Returns a zero count; the runbook decides.
-- ============================================================================

CREATE OR REPLACE FUNCTION deployment.f_p01_plan(
    p_run_id   integer,
    p_pipeline text DEFAULT NULL
)
 RETURNS TABLE(deployment_id integer, run_id integer, objects_planned integer)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_dep_id   int;
    v_pipeline text;
    v_count    int;
BEGIN
    SELECT r.deployment_id INTO v_dep_id
      FROM deployment.deployment_runs r
     WHERE r.id = p_run_id;

    IF v_dep_id IS NULL THEN
        RAISE EXCEPTION 'f_p01_plan: no such run % (call start_run first)', p_run_id;
    END IF;

    IF p_pipeline IS NOT NULL THEN
        v_pipeline := p_pipeline;
    ELSE
        SELECT p.name INTO v_pipeline
          FROM deployment.deployments d
          LEFT JOIN deployment.pipelines p ON p.id = d.pipeline_id
         WHERE d.id = v_dep_id;
    END IF;

    -- Idempotent re-plan: start clean rather than double-insert objects.
    -- Qualify the column: the RETURNS TABLE OUT param is also named run_id,
    -- so a bare `run_id` here is ambiguous (caught in test, 2026-10-05).
    DELETE FROM deployment.deployment_objects
     WHERE deployment_objects.run_id = p_run_id;

    INSERT INTO deployment.deployment_objects
        (run_id, seq, pipeline_id, platform, schema_path, object_type, action, status)
    SELECT p_run_id,
           row_number() OVER (ORDER BY m.seq),
           p.id,
           m.platform,
           m.schema_path,
           m.object_type,
           CASE
             WHEN m.object_type <> 'table' THEN 'replace'
             WHEN m.data = 'seed_once'      THEN 'seed'
             WHEN m.data = 'refresh_always' THEN 'refresh'
             ELSE 'replace'
           END,
           'pending'
      FROM deployment.vw_manifest m
      LEFT JOIN deployment.pipelines p ON p.name = m.pipeline
     WHERE v_pipeline IS NULL OR m.pipeline = v_pipeline;

    GET DIAGNOSTICS v_count = ROW_COUNT;

    UPDATE deployment.deployment_runs
       SET status = 'planned'
     WHERE id = p_run_id
       AND status NOT IN ('failed', 'succeeded');

    RETURN QUERY SELECT v_dep_id, p_run_id, v_count;
END
$function$
;
