CREATE OR REPLACE FUNCTION whatsfresh.c_getval(p_param_name text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  -- account_id falls back to the user's default account when the stored value is empty (task 697), so a cleared
  -- or never-set active account can never blank out every api_ function.
  SELECT coalesce(
    (SELECT context->>p_param_name FROM whatsfresh.api_context_store(current_setting('app.current_email', true))),
    CASE WHEN p_param_name = 'account_id' THEN
      (SELECT u.default_account_id::text FROM whatsfresh.users u
        WHERE u.email = current_setting('app.current_email', true) AND u.deleted_at IS NULL)
    END)
$function$
;

