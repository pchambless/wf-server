CREATE OR REPLACE FUNCTION deployment.f_assert_distinct_target(p_dblink_server text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_local  text;
  v_remote text;
BEGIN
  -- Hard stop: a deploy's source (this database) and its target must be
  -- DIFFERENT Postgres clusters. Compared by system_identifier, not by name or
  -- flag: dev and prod both call their database 'n8n', and an is_target flag can
  -- be flipped back. Incident 2026-10-09 (task 517): a live run with
  -- environment=dev resolved pg_dev_server to this same cluster, TRUNCATEd the
  -- target's refresh tables and reloaded them from themselves - dev's studio
  -- css/page_components/action_* were wiped. Never again.
  SELECT system_identifier::text INTO v_local FROM pg_control_system();
  SELECT x.sid INTO v_remote
    FROM dblink(p_dblink_server, 'SELECT system_identifier::text FROM pg_control_system()') AS x(sid text);

  IF v_remote IS NULL THEN
    RAISE EXCEPTION 'f_assert_distinct_target: could not read system_identifier from %', p_dblink_server;
  END IF;
  IF v_remote = v_local THEN
    RAISE EXCEPTION 'f_assert_distinct_target: dblink server % is THIS cluster (system_identifier %) - source and target must be different environments', p_dblink_server, v_local;
  END IF;
END
$function$
;

