CREATE OR REPLACE FUNCTION whatsfresh.f_recall_plan(p_account_id integer)
 RETURNS TABLE(account_name text, coordinator text, backup text, sales_records text, notify_by text, disposition text, state_contact text, default_coordinator text, saved jsonb)
 LANGUAGE sql
 STABLE
AS $function$
  -- Default coordinator: the account's owner, preferring a business owner over WhatsFresh staff (role 1), who are
  -- owners on many accounts.
  WITH a AS (
    SELECT ac.id, ac.name FROM whatsfresh.accounts ac WHERE ac.id = p_account_id
  ), s AS (
    SELECT coalesce(st.settings -> 'recall_plan', '{}'::jsonb) AS p
      FROM a LEFT JOIN whatsfresh.account_settings st ON st.account_id = a.id AND st.deleted_at IS NULL
  ), o AS (
    SELECT coalesce((
      SELECT nullif(btrim(concat_ws(' ', u.first_name, u.last_name)), '')
        FROM whatsfresh.accounts_users au
        JOIN whatsfresh.users u ON u.id = au.user_id AND u.deleted_at IS NULL
       WHERE au.account_id = p_account_id AND au.is_owner = 1 AND au.deleted_at IS NULL
       ORDER BY (u.role = 1), au.id
       LIMIT 1), 'the account owner') AS owner_name
  )
  SELECT a.name::text,
         coalesce(nullif(btrim(s.p ->> 'coordinator'), ''), o.owner_name),
         nullif(btrim(s.p ->> 'backup'), ''),
         coalesce(nullif(btrim(s.p ->> 'sales_records'), ''), 'your invoices'),
         coalesce(nullif(btrim(s.p ->> 'notify_by'), ''), 'phone'),
         coalesce(nullif(btrim(s.p ->> 'disposition'), ''), 'destroyed'),
         coalesce(nullif(btrim(s.p ->> 'state_contact'), ''), 'Missouri DHSS'),
         o.owner_name,
         s.p
    FROM a CROSS JOIN s CROSS JOIN o
$function$
;

