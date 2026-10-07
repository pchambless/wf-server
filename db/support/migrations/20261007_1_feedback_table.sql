-- 2026-10-07 task 477, step 1: support.feedback table + vw_feedback + intake schema (function superseded by step 2)
SET ROLE wf_admin;

-- support.feedback: dev-only home for ALL feedback (task 477). NO FK to whatsfresh.accounts on
-- purpose: etl.p01_l01 TRUNCATEs whatsfresh.accounts weekly and Postgres refuses while any
-- outside table references it (that is what broke the 2026-10-04 ETL run).
CREATE TABLE support.feedback (
  id          integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  account_id  integer NOT NULL,
  email       text    NOT NULL,
  page_id     integer NOT NULL REFERENCES studio.pages(id),
  title       text    NOT NULL,
  category    text    NOT NULL,
  message     text    NOT NULL,
  status      text    NOT NULL DEFAULT 'new',
  source_env  text    NOT NULL DEFAULT 'dev',
  task_id     integer REFERENCES agile.agile_cache(id),
  created_at  timestamp DEFAULT now(),
  created_by  text,
  updated_at  timestamp,
  updated_by  text,
  deleted_at  timestamp,
  deleted_by  text,
  CONSTRAINT feedback_category_check CHECK (category = ANY (ARRAY['bug','suggestion','question','praise','other'])),
  CONSTRAINT feedback_source_env_check CHECK (source_env = ANY (ARRAY['dev','prod','local']))
);

INSERT INTO support.feedback (id, account_id, email, page_id, title, category, message, status, created_at, created_by, updated_at, updated_by, deleted_at, deleted_by)
OVERRIDING SYSTEM VALUE
SELECT id, account_id, email, page_id, title, category, message, status, created_at, created_by, updated_at, updated_by, deleted_at, deleted_by
FROM whatsfresh.feedback;

SELECT setval(pg_get_serial_sequence('support.feedback', 'id'), (SELECT max(id) FROM support.feedback));

CREATE TRIGGER trg_touch_updated_at BEFORE UPDATE ON support.feedback
  FOR EACH ROW EXECUTE FUNCTION deployment.f_touch_updated_at();

CREATE VIEW support.vw_feedback AS
SELECT f.id, f.account_id, a.name AS account_name, f.email,
       (u.first_name::text || ' ' || u.last_name::text) AS user_name,
       f.page_id, p.page_name, f.title, f.category, f.message, f.status,
       f.source_env, f.task_id, f.created_at, f.created_by, f.updated_at, f.updated_by,
       f.deleted_at, f.deleted_by
  FROM support.feedback f
  LEFT JOIN whatsfresh.accounts a ON a.id = f.account_id
  LEFT JOIN whatsfresh.users u ON u.email::text = f.email
  LEFT JOIN studio.pages p ON p.id = f.page_id
 WHERE f.deleted_at IS NULL;

-- The doorway for prod -> dev writes (task 477). One function per dev-owned table; a restricted
-- role gets EXECUTE on this schema only (role + pg_hba are created by Paul, not here).
CREATE SCHEMA IF NOT EXISTS intake;

CREATE OR REPLACE FUNCTION intake.feedback(
  p_email text, p_account_id integer, p_page_id integer,
  p_title text, p_category text, p_message text, p_source_env text DEFAULT 'dev')
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, support, studio
AS $fn$
DECLARE
  v_id integer;
BEGIN
  IF coalesce(btrim(p_email), '') = '' OR coalesce(btrim(p_title), '') = '' OR coalesce(btrim(p_message), '') = '' THEN
    RAISE EXCEPTION 'intake.feedback: email, title and message are required';
  END IF;
  IF p_source_env NOT IN ('dev', 'prod', 'local') THEN
    RAISE EXCEPTION 'intake.feedback: unknown source_env %', p_source_env;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM studio.pages WHERE id = p_page_id) THEN
    RAISE EXCEPTION 'intake.feedback: unknown page_id %', p_page_id;
  END IF;

  INSERT INTO support.feedback (account_id, email, page_id, title, category, message, source_env, created_by)
  VALUES (coalesce(p_account_id, 0), btrim(p_email), p_page_id, btrim(p_title),
          CASE WHEN p_category IN ('bug','suggestion','question','praise','other') THEN p_category ELSE 'other' END,
          p_message, p_source_env, btrim(p_email))
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$fn$;

REVOKE ALL ON FUNCTION intake.feedback(text, integer, integer, text, text, text, text) FROM PUBLIC;
