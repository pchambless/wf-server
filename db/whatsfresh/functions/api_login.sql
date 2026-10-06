CREATE OR REPLACE FUNCTION whatsfresh.api_login(p_email text)
 RETURNS TABLE(user_id integer, email text, password text, first_name text, last_name text, role_id integer, default_account_id integer)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT 
        a.id,
        a.email::text,
        a.password::text,
        a.first_name::text,
        a.last_name::text,
        a.role::int,
        a.default_account_id::int
    FROM whatsfresh.users a
    WHERE a.email = p_email
    AND a.deleted_at IS NULL
    LIMIT 1;
END;
$function$
;

