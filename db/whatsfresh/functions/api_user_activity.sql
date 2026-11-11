CREATE OR REPLACE FUNCTION whatsfresh.api_user_activity(p_user_id integer, p_days integer DEFAULT 7)
 RETURNS TABLE(account_id integer, account text, created bigint, edited bigint, deleted bigint, batches bigint, last_activity text)
 LANGUAGE sql
 STABLE
AS $function$
  -- Accounts a user touched in the last p_days days: the per-table counts rolled up by account.
  SELECT t.account_id,
         t.account,
         sum(t.created)::bigint,
         sum(t.edited)::bigint,
         sum(t.deleted)::bigint,
         COALESCE(sum(t.created) FILTER (WHERE t.tbl = 'batches'), 0)::bigint,
         max(t.last_activity)
    FROM whatsfresh.api_user_activity_tables(p_user_id, p_days) t
   GROUP BY t.account_id, t.account
   ORDER BY max(t.last_activity) DESC
$function$
;
