CREATE OR REPLACE FUNCTION studio.f_batch_map(p_mode text, p_event_type text, p_map_id integer, p_email text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_ctx      jsonb;
  v_account  integer;
  v_source   integer;
  v_target   integer;
  v_user     text;
  v_result   jsonb;
BEGIN
  IF p_email IS NULL OR NOT EXISTS (SELECT 1 FROM whatsfresh.users u WHERE lower(u.email) = lower(p_email) AND u.deleted_at IS NULL) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not allowed');
  END IF;

  IF p_mode = 'INSERT' THEN
    SELECT cs.context INTO v_ctx FROM whatsfresh.api_context_store(p_email) cs;
    v_account := CASE WHEN v_ctx ->> 'account_id' ~ '^[0-9]+\Z' THEN (v_ctx ->> 'account_id')::integer END;
    v_source  := CASE WHEN v_ctx ->> 'source_batch_id' ~ '^[0-9]+\Z' THEN (v_ctx ->> 'source_batch_id')::integer END;
    v_target  := CASE WHEN v_ctx ->> 'target_batch_id' ~ '^[0-9]+\Z' THEN (v_ctx ->> 'target_batch_id')::integer END;
    v_user    := coalesce(v_ctx ->> 'firstName', p_email);

    -- Both batches must belong to the account the caller may write to.
    IF v_account IS NULL OR v_source IS NULL OR v_target IS NULL
       OR NOT whatsfresh.f_can_access_account(p_email, v_account)
       OR studio.f_dml_row_account('batches', v_source) IS DISTINCT FROM v_account
       OR studio.f_dml_row_account('batches', v_target) IS DISTINCT FROM v_account THEN
      RETURN jsonb_build_object('success', false, 'error', 'Not allowed');
    END IF;

    BEGIN
      INSERT INTO whatsfresh.lineage (account_id, event_type, source_batch_id, target_batch_id, created_at, created_by)
      VALUES (v_account, coalesce(nullif(p_event_type, ''), 'Shop->Prod'), v_source, v_target, now(), v_user)
      RETURNING to_jsonb(lineage.*) INTO v_result;
    EXCEPTION WHEN unique_violation THEN
      RETURN jsonb_build_object('success', false, 'error', 'These batches are already mapped');
    END;

    RETURN jsonb_build_object('success', true, 'mode', 'insert', 'data', v_result);
  ELSIF p_mode = 'DELETE' THEN
    IF p_map_id IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error', 'DELETE requires map_id');
    END IF;

    v_account := studio.f_dml_row_account('lineage', p_map_id);
    IF v_account IS NULL OR NOT whatsfresh.f_can_access_account(p_email, v_account) THEN
      RETURN jsonb_build_object('success', false, 'error', format('Row not found: id=%s', p_map_id));
    END IF;

    DELETE FROM whatsfresh.lineage WHERE id = p_map_id RETURNING to_jsonb(lineage.*) INTO v_result;
    RETURN jsonb_build_object('success', true, 'mode', 'hard-delete', 'data', v_result);
  END IF;

  RETURN jsonb_build_object('success', false, 'error', 'Invalid mode: ' || coalesce(p_mode, 'NULL'));
END
$function$
;

