CREATE OR REPLACE FUNCTION whatsfresh.c_getval(p_param_name text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$ SELECT context->>p_param_name FROM whatsfresh.api_context_store(current_setting('app.current_email', true)); $function$
;

