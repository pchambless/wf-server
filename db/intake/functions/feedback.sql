CREATE OR REPLACE FUNCTION intake.feedback(p_email text, p_account_id integer, p_page_id integer, p_title text, p_category text, p_message text, p_source_env text DEFAULT 'dev'::text)
 RETURNS TABLE(id integer, title text, category text, message text, user_name text, page_name text, account_name text, source_env text, submitted text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'support', 'studio', 'whatsfresh'
AS $function$
DECLARE
  v_id integer;
BEGIN
  IF coalesce(btrim(p_email), '') = '' OR coalesce(btrim(p_title), '') = '' OR coalesce(btrim(p_message), '') = '' THEN
    RAISE EXCEPTION 'intake.feedback: email, title and message are required';
  END IF;
  IF p_source_env NOT IN ('dev', 'prod', 'local') THEN
    RAISE EXCEPTION 'intake.feedback: unknown source_env %', p_source_env;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM studio.pages sp WHERE sp.id = p_page_id) THEN
    RAISE EXCEPTION 'intake.feedback: unknown page_id %', p_page_id;
  END IF;

  INSERT INTO support.feedback AS f (account_id, email, page_id, title, category, message, source_env, created_by)
  VALUES (coalesce(p_account_id, 0), btrim(p_email), p_page_id, btrim(p_title),
          CASE WHEN p_category IN ('bug','suggestion','question','praise','other') THEN p_category ELSE 'other' END,
          p_message, p_source_env, btrim(p_email))
  RETURNING f.id INTO v_id;

  -- Everything the Slack notification needs, so the caller (including prod's restricted
  -- login) never has to read any table itself.
  RETURN QUERY
  SELECT f.id, f.title, f.category, f.message,
         coalesce(nullif(btrim(u.first_name::text || ' ' || u.last_name::text), ''), f.email),
         sp.page_name::text,
         coalesce(a.name::text, 'account ' || f.account_id),
         f.source_env,
         to_char(f.created_at, 'YYYY-MM-DD')
    FROM support.feedback f
    JOIN studio.pages sp ON sp.id = f.page_id
    LEFT JOIN whatsfresh.users u ON u.email::text = f.email
    LEFT JOIN whatsfresh.accounts a ON a.id = f.account_id
   WHERE f.id = v_id;
END;
$function$
;
