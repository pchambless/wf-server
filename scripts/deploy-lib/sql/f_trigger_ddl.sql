CREATE OR REPLACE FUNCTION deployment.f_trigger_ddl(p_schema text, p_table text)
 RETURNS text
 LANGUAGE sql
AS $function$
    -- Re-runnable DDL for a table's triggers: each CREATE TRIGGER is guarded by name via pg_trigger
    -- (Postgres has no CREATE TRIGGER IF NOT EXISTS before 14, and dev/prod differ).
    -- Triggers whose function lives in the deployment schema are dev-only tooling and are skipped;
    -- that schema is not on prod. Runs after the function phase (see f_p02_structure) because a trigger
    -- needs its function to exist on the target.
    SELECT string_agg(
             format(E'DO $trg$\nBEGIN\n  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = %L AND tgrelid = %L::regclass) THEN\n    %s;\n  END IF;\nEND\n$trg$;',
                    tg.tgname, p_schema || '.' || p_table, pg_get_triggerdef(tg.oid)),
             E'\n' ORDER BY tg.tgname)
      FROM pg_trigger tg
      JOIN pg_class c ON c.oid = tg.tgrelid
      JOIN pg_namespace n ON n.oid = c.relnamespace
      JOIN pg_proc fp ON fp.oid = tg.tgfoid
      JOIN pg_namespace fn ON fn.oid = fp.pronamespace
     WHERE n.nspname = p_schema AND c.relname = p_table
       AND NOT tg.tgisinternal AND fn.nspname <> 'deployment'
$function$
;
