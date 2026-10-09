CREATE OR REPLACE FUNCTION deployment.f_open_release_task(p_env text, p_summary text DEFAULT NULL::text, p_sprint text DEFAULT NULL::text, p_by text DEFAULT 'deploy'::text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_epic    integer;
  v_sprint  integer;
  v_name    text;
  v_cutover text;
  v_task    integer;
  v_incl    text;
BEGIN
  -- One release task per live prod deploy, filed under the Releases epic: the
  -- pre_launch sprint before go-live, then one sprint per month (created here
  -- when missing, so nobody has to remember). p_sprint overrides (e.g. the go-live sprint).
  SELECT id INTO v_epic FROM agile.agile_cache
   WHERE page_type = 'Epic' AND page_name = 'Releases' AND deleted_at IS NULL ORDER BY id LIMIT 1;
  IF v_epic IS NULL THEN
    RAISE EXCEPTION 'f_open_release_task: no "Releases" epic in agile_cache';
  END IF;

  SELECT notes ->> 'cutover_status' INTO v_cutover FROM deployment.environments WHERE name = 'prod';
  v_name := coalesce(nullif(p_sprint, ''),
                     CASE WHEN coalesce(v_cutover, 'pre_launch') = 'pre_launch' THEN 'Pre-launch deploys'
                          ELSE 'Releases ' || to_char(now() AT TIME ZONE 'America/Chicago', 'YYYY-MM') END);

  SELECT id INTO v_sprint FROM agile.agile_cache
   WHERE page_type = 'Sprint' AND parent_id = v_epic AND page_name = v_name AND deleted_at IS NULL ORDER BY id LIMIT 1;
  IF v_sprint IS NULL THEN
    INSERT INTO agile.agile_cache (page_name, page_type, parent_id, status, priority, description, created_by)
    VALUES (v_name, 'Sprint', v_epic, 'In Progress', 'Medium', 'Why: prod deploys in ' || v_name || '.', p_by)
    RETURNING id INTO v_sprint;
  END IF;

  -- tasks Done but not yet shipped by a live prod deploy = what this release carries
  SELECT string_agg('Task ' || a.id || ': ' || a.page_name, E'\n' ORDER BY a.id)
    INTO v_incl
    FROM (SELECT a.id, a.page_name
            FROM agile.vw_task_deployed t
            JOIN agile.agile_cache a ON a.id = t.task_id
           WHERE t.deployed_on IS NULL
             AND a.parent_id NOT IN (SELECT id FROM agile.agile_cache WHERE parent_id = v_epic AND deleted_at IS NULL)
           ORDER BY a.id DESC LIMIT 60) a;

  INSERT INTO agile.agile_cache (page_name, page_type, parent_id, status, priority, description, created_by)
  VALUES ('Deploy ' || to_char(now() AT TIME ZONE 'America/Chicago', 'YYYY-MM-DD') || ' (' || p_env || '): ' || coalesce(nullif(p_summary, ''), 'release'),
          'Task', v_sprint, 'In Progress', 'Medium',
          'Release task for a live ' || p_env || ' deploy, opened with the run. Marked Done when the run succeeds, Blocked if a step fails. Its impacts are the object-level changes captured by the run.'
            || E'\n\nTasks done and not yet shipped by an earlier live prod deploy:\n' || coalesce(v_incl, '(none)'),
          p_by)
  RETURNING id INTO v_task;

  RETURN v_task;
END
$function$
;

