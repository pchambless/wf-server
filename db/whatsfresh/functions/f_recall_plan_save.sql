CREATE OR REPLACE FUNCTION whatsfresh.f_recall_plan_save(p_account_id integer, p_email text, p_answers jsonb, p_user text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_plan jsonb;
  v_row  jsonb;
BEGIN
  IF p_account_id IS NULL OR NOT EXISTS (
       SELECT 1 FROM whatsfresh.users u
        WHERE lower(u.email) = lower(p_email) AND u.deleted_at IS NULL
          AND (u.role = 1 OR EXISTS (SELECT 1 FROM whatsfresh.accounts_users au
                                      WHERE au.user_id = u.id AND au.account_id = p_account_id
                                        AND au.is_owner = 1 AND au.deleted_at IS NULL))) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Only an account owner can change the recall plan');
  END IF;

  -- Known answers only, trimmed, at most 200 characters; an empty answer is left out so its default applies.
  SELECT coalesce(jsonb_object_agg(k, left(btrim(p_answers ->> k), 200)), '{}'::jsonb) INTO v_plan
    FROM unnest(ARRAY['coordinator', 'backup', 'sales_records', 'notify_by', 'disposition', 'state_contact']) k
   WHERE nullif(btrim(p_answers ->> k), '') IS NOT NULL;

  -- A soft-deleted row is revived with only the plan: its old settings stay gone (e.g. a removed token).
  INSERT INTO whatsfresh.account_settings AS st (account_id, settings, created_at, created_by)
  VALUES (p_account_id, jsonb_build_object('recall_plan', v_plan), now(), p_user)
  ON CONFLICT (account_id) DO UPDATE
     SET settings = CASE WHEN st.deleted_at IS NULL THEN coalesce(st.settings, '{}'::jsonb) ELSE '{}'::jsonb END
                    || jsonb_build_object('recall_plan', v_plan),
         deleted_at = NULL, deleted_by = NULL,
         updated_at = now(), updated_by = p_user
  RETURNING jsonb_build_object('account_id', st.account_id, 'recall_plan', st.settings -> 'recall_plan') INTO v_row;

  RETURN jsonb_build_object('success', true, 'mode', 'insert', 'data', v_row);
END
$function$
;

