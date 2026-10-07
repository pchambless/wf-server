-- 2026-10-07 task 477, step 4: main-app Feedback form is insert-only; hide in-app triage; old whatsfresh.feedback/vw_feedback dropped separately
SET ROLE wf_admin;
BEGIN;
-- The in-app Feedback form is INSERT-only now (triage moved to the support app), so its hydrate
-- is the blank row only - no read of whatsfresh.feedback.
UPDATE studio.html_templates SET hydrate = $h$SELECT NULL::integer AS f_id,
  whatsfresh.c_getval('account_id')::integer AS f_account_id,
  whatsfresh.c_getval('userEmail') AS f_email,
  whatsfresh.c_getval('page_id')::integer AS f_page_id,
  NULL::text AS f_title, NULL::text AS f_category, NULL::text AS f_message$h$
 WHERE name = 'feedback_form';
-- Hide the in-app triage: menu item (Admin > Feedback) and the grid on page 102.
UPDATE studio.action_components SET deleted_at = now(), deleted_by = 'claude' WHERE id = 52 AND label = 'Feedback' AND deleted_at IS NULL;
UPDATE studio.page_components SET deleted_at = now(), deleted_by = 'claude' WHERE id = 83 AND comp_name = 'feedback_grid' AND deleted_at IS NULL;
COMMIT;
SELECT set_config('app.current_email', 'Demo@wf.com', false);
SELECT f_account_id, f_email, f_page_id, f_title FROM (SELECT hydrate FROM studio.html_templates WHERE name='feedback_form') t, LATERAL (SELECT 1) x LIMIT 0;

-- (applied separately) DROP VIEW whatsfresh.vw_feedback; DROP TABLE whatsfresh.feedback;  knowledge_base.objects 159,160 set obsolete
