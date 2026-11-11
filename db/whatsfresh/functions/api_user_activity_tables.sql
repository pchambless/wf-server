CREATE OR REPLACE FUNCTION whatsfresh.api_user_activity_tables(p_user_id integer, p_days integer DEFAULT 7)
 RETURNS TABLE(account_id integer, account text, tbl text, created bigint, edited bigint, deleted bigint, last_activity text)
 LANGUAGE sql
 STABLE
AS $function$
  -- Per account and table: what a user created, edited and deleted in the last p_days days, from the audit
  -- columns on each row. The row stamp is the user's email (v2) or first name (legacy copies); a first name
  -- only counts when no other live user shares it. Hard-deleted lineage rows are not visible here.
  WITH u AS (
    SELECT lower(us.email) AS email,
           CASE WHEN (SELECT count(*) FROM whatsfresh.users o
                       WHERE o.deleted_at IS NULL AND lower(o.first_name) = lower(us.first_name)) = 1
                THEN lower(us.first_name) END AS first_name
      FROM whatsfresh.users us WHERE us.id = p_user_id
  ),
  src AS (
    SELECT t.account_id, 'batches' AS tbl, t.created_at, t.created_by, t.updated_at, t.updated_by, t.deleted_at, t.deleted_by FROM whatsfresh.batches t
    UNION ALL SELECT t.account_id, 'account_settings', t.created_at, t.created_by, t.updated_at, t.updated_by, t.deleted_at, t.deleted_by FROM whatsfresh.account_settings t
    UNION ALL SELECT t.account_id, 'accounts_users', t.created_at, t.created_by, t.updated_at, t.updated_by, t.deleted_at, t.deleted_by FROM whatsfresh.accounts_users t
    UNION ALL SELECT t.account_id, 'brands', t.created_at, t.created_by, t.updated_at, t.updated_by, t.deleted_at, t.deleted_by FROM whatsfresh.brands t
    UNION ALL SELECT t.account_id, 'entities', t.created_at, t.created_by, t.updated_at, t.updated_by, t.deleted_at, t.deleted_by FROM whatsfresh.entities t
    UNION ALL SELECT t.account_id, 'entity_types', t.created_at, t.created_by, t.updated_at, t.updated_by, t.deleted_at, t.deleted_by FROM whatsfresh.entity_types t
    UNION ALL SELECT t.account_id, 'locations', t.created_at, t.created_by, t.updated_at, t.updated_by, t.deleted_at, t.deleted_by FROM whatsfresh.locations t
    UNION ALL SELECT t.account_id, 'measures', t.created_at, t.created_by, t.updated_at, t.updated_by, t.deleted_at, t.deleted_by FROM whatsfresh.measures t
    UNION ALL SELECT t.account_id, 'tasks', t.created_at, t.created_by, t.updated_at, t.updated_by, t.deleted_at, t.deleted_by FROM whatsfresh.tasks t
    UNION ALL SELECT t.account_id, 'workers', t.created_at, t.created_by, t.updated_at, t.updated_by, t.deleted_at, t.deleted_by FROM whatsfresh.workers t
    UNION ALL SELECT t.account_id, 'lineage', t.created_at, t.created_by, NULL, NULL, NULL, NULL FROM whatsfresh.lineage t
    UNION ALL SELECT e.account_id, 'product_recipes', t.created_at, t.created_by, t.updated_at, t.updated_by, t.deleted_at, t.deleted_by
      FROM whatsfresh.product_recipes t JOIN whatsfresh.entities e ON e.id = t.product_id
    UNION ALL SELECT b.account_id, 'product_batch_tasks', t.created_at, t.created_by, t.updated_at, t.updated_by, t.deleted_at, t.deleted_by
      FROM whatsfresh.product_batch_tasks t JOIN whatsfresh.batches b ON b.id = t.batch_id
  ),
  ev AS (
    SELECT s.account_id, s.tbl, 'created' AS kind, s.created_at AS ts, s.created_by AS who FROM src s
    UNION ALL SELECT s.account_id, s.tbl, 'edited', s.updated_at, s.updated_by FROM src s
      WHERE s.updated_at > s.created_at + interval '2 seconds'
    UNION ALL SELECT s.account_id, s.tbl, 'deleted', s.deleted_at, s.deleted_by FROM src s
      WHERE s.deleted_at IS NOT NULL
  ),
  mine AS (
    SELECT ev.* FROM ev, u
     WHERE ev.ts >= now() - make_interval(days => GREATEST(p_days, 1))
       AND lower(ev.who) IN (u.email, u.first_name)
  )
  SELECT m.account_id,
         a.name::text,
         m.tbl,
         count(*) FILTER (WHERE m.kind = 'created'),
         count(*) FILTER (WHERE m.kind = 'edited'),
         count(*) FILTER (WHERE m.kind = 'deleted'),
         to_char((max(m.ts) AT TIME ZONE 'UTC') AT TIME ZONE 'America/Chicago', 'YYYY-MM-DD HH24:MI')
    FROM mine m
    LEFT JOIN whatsfresh.accounts a ON a.id = m.account_id
   GROUP BY m.account_id, a.name, m.tbl
   ORDER BY max(m.ts) DESC, m.tbl
$function$
;
