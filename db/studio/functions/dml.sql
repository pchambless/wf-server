CREATE OR REPLACE FUNCTION studio.dml(p_page_id integer, p_mode text, p_data jsonb DEFAULT NULL::jsonb, p_pk_val integer DEFAULT NULL::integer, p_user text DEFAULT 'system'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_schema        text;
    v_table         text;
    v_pk_col        text;
    v_head_col      text;
    v_parent_ids    text;
    v_parent_key    text;
    v_parent_val    text;
    v_sql           text;
    v_cols          text;
    v_vals          text;
    v_sets          text;
    v_result        jsonb;
    v_head_val      text;
    v_existing      integer;
    v_cu_success    boolean;
    v_cu_user_id    integer;
    v_cu_error      text;
    v_constraint    text;
BEGIN
    SELECT
        split_part(vp.table_name, '.', 1),
        split_part(vp.table_name, '.', 2),
        vp.table_id,
        vp.form_head_col,
        vp.parent_id
    INTO v_schema, v_table, v_pk_col, v_head_col, v_parent_ids
    FROM studio.vw_pages vp
    WHERE vp.page_id = p_page_id;

    IF v_table IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', format('Page not found or no table configured: page_id=%s', p_page_id));
    END IF;

    IF p_mode NOT IN ('INSERT', 'UPDATE', 'DELETE') THEN
        RETURN jsonb_build_object('success', false, 'error', 'Invalid mode: ' || coalesce(p_mode, 'NULL'));
    END IF;

    IF p_data IS NULL THEN
        p_data := '{}'::jsonb;
    END IF;

    p_user := coalesce(whatsfresh.c_getval('firstName'), p_user);

    IF v_parent_ids IS NOT NULL AND v_parent_ids <> '[]' THEN
        FOR v_parent_key IN
            SELECT trim(unnest(string_to_array(trim(both '[]' from v_parent_ids), ',')))
        LOOP
            v_parent_key := trim(v_parent_key);
            IF v_parent_key <> '' AND (NOT (p_data ? v_parent_key) OR p_data ->> v_parent_key IS NULL) THEN
                v_parent_val := whatsfresh.c_getval(v_parent_key);
                IF v_parent_val IS NOT NULL THEN
                    p_data := p_data || jsonb_build_object(v_parent_key, v_parent_val);
                END IF;
            END IF;
        END LOOP;
    END IF;

    -- ===================
    -- SPECIAL CASE: whatsfresh.users INSERT cannot go through generic
    -- column-write DML - password needs crypt() hashing and creation may
    -- need to link an accounts_users row atomically. Delegate to
    -- api_create_user instead of building a raw INSERT. UPDATE/DELETE for
    -- this table stay fully generic (the users form never submits a
    -- password field on edit - see task 234).
    -- ===================
    IF p_mode = 'INSERT' AND v_schema = 'whatsfresh' AND v_table = 'users' THEN
        IF (p_data ->> 'password') IS DISTINCT FROM (p_data ->> 'confirm_password') THEN
            RETURN jsonb_build_object('success', false, 'error', 'Password and confirm password do not match');
        END IF;

        SELECT cu.success, cu.user_id, cu.error_message
        INTO v_cu_success, v_cu_user_id, v_cu_error
        FROM whatsfresh.api_create_user(
            p_data ->> 'email',
            p_data ->> 'password',
            p_data ->> 'first_name',
            p_data ->> 'last_name',
            (p_data ->> 'role')::integer,
            p_user,
            true,
            NULLIF(p_data ->> 'default_account_id', '')::integer
        ) cu;

        IF NOT v_cu_success THEN
            RETURN jsonb_build_object('success', false, 'error', v_cu_error);
        END IF;

        SELECT to_jsonb(u.*) - 'password' INTO v_result FROM whatsfresh.users u WHERE u.id = v_cu_user_id;
        RETURN jsonb_build_object('success', true, 'mode', 'insert', 'data', v_result);
    END IF;

    IF p_mode = 'DELETE' THEN
        IF p_pk_val IS NULL THEN
            RETURN jsonb_build_object('success', false, 'error', 'DELETE requires p_pk_val');
        END IF;

        v_sql := format(
            'DELETE FROM %I.%I WHERE %I = %s RETURNING to_jsonb(%I.*)',
            v_schema, v_table, v_pk_col, p_pk_val, v_table
        );
        BEGIN
            EXECUTE v_sql INTO v_result;

            IF v_result IS NULL THEN
                RETURN jsonb_build_object('success', false, 'error', format('Row not found: %s=%s', v_pk_col, p_pk_val));
            END IF;

            RETURN jsonb_build_object('success', true, 'mode', 'hard-delete', 'data', v_result);
        EXCEPTION
            WHEN foreign_key_violation THEN
                v_sql := format(
                    'UPDATE %I.%I SET deleted_at = now(), deleted_by = %L, updated_at = now() WHERE %I = %s RETURNING to_jsonb(%I.*)',
                    v_schema, v_table, p_user, v_pk_col, p_pk_val, v_table
                );
                EXECUTE v_sql INTO v_result;

                IF v_result IS NULL THEN
                    RETURN jsonb_build_object('success', false, 'error', format('Row not found: %s=%s', v_pk_col, p_pk_val));
                END IF;

                RETURN jsonb_build_object('success', true, 'mode', 'soft-delete', 'data', v_result);
            WHEN OTHERS THEN
                RETURN jsonb_build_object('success', false, 'error', SQLERRM);
        END;
    END IF;

    IF p_mode = 'UPDATE' THEN
        IF p_pk_val IS NULL THEN
            RETURN jsonb_build_object('success', false, 'error', 'UPDATE requires p_pk_val');
        END IF;

        IF p_data = '{}'::jsonb THEN
            RETURN jsonb_build_object('success', false, 'error', 'No fields to update');
        END IF;

        SELECT string_agg(format('%I = %L', key, NULLIF(value #>> '{}', '')), ', ')
        INTO v_sets
        FROM jsonb_each(p_data);

        v_sets := v_sets || format(', updated_at = now(), updated_by = %L', p_user);

        v_sql := format(
            'UPDATE %I.%I SET %s WHERE %I = %s RETURNING to_jsonb(%I.*)',
            v_schema, v_table, v_sets, v_pk_col, p_pk_val, v_table
        );

        BEGIN
            EXECUTE v_sql INTO v_result;
        EXCEPTION
            WHEN OTHERS THEN
                RETURN jsonb_build_object('success', false, 'error', SQLERRM);
        END;

        IF v_result IS NULL THEN
            RETURN jsonb_build_object('success', false, 'error', format('Row not found: %s=%s', v_pk_col, p_pk_val));
        END IF;

        RETURN jsonb_build_object('success', true, 'mode', 'update', 'data', v_result);
    END IF;

    IF p_mode = 'INSERT' THEN
        IF p_data = '{}'::jsonb THEN
            RETURN jsonb_build_object('success', false, 'error', 'INSERT requires p_data');
        END IF;

        IF v_head_col IS NOT NULL AND p_data ? v_head_col THEN
            v_head_val := p_data ->> v_head_col;

            v_sql := format(
                'SELECT %I FROM %I.%I WHERE %I = %L AND deleted_at IS NULL',
                v_pk_col, v_schema, v_table, v_head_col, v_head_val
            );

            IF v_parent_ids IS NOT NULL AND v_parent_ids <> '[]' THEN
                FOR v_parent_key IN
                    SELECT trim(unnest(string_to_array(trim(both '[]' from v_parent_ids), ',')))
                LOOP
                    v_parent_key := trim(v_parent_key);
                    IF v_parent_key <> '' AND p_data ? v_parent_key THEN
                        v_parent_val := p_data ->> v_parent_key;
                        v_sql := v_sql || format(' AND %I = %L', v_parent_key, v_parent_val);
                    END IF;
                END LOOP;
            END IF;

            v_sql := v_sql || ' LIMIT 1';
            EXECUTE v_sql INTO v_existing;

            IF v_existing IS NOT NULL THEN
                RETURN jsonb_build_object(
                    'success', false,
                    'error', format('%s ''%s'' already exists (id=%s)', v_head_col, v_head_val, v_existing)
                );
            END IF;
        END IF;

        SELECT
            string_agg(format('%I', key), ', '),
            string_agg(format('%L', NULLIF(value #>> '{}', '')), ', ')
        INTO v_cols, v_vals
        FROM jsonb_each(p_data);

        v_cols := v_cols || ', created_at, created_by';
        v_vals := v_vals || format(', now(), %L', p_user);

        v_sql := format(
            'INSERT INTO %I.%I (%s) VALUES (%s) RETURNING to_jsonb(%I.*)',
            v_schema, v_table, v_cols, v_vals, v_table
        );

        BEGIN
            EXECUTE v_sql INTO v_result;
        EXCEPTION
            WHEN unique_violation THEN
                GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;

                -- Only tables with a form_head_col configured can look up a
                -- soft-deleted row to reactivate (that lookup needs a column to
                -- match on). Without one, go straight to a clean duplicate message
                -- instead of running a query built from a NULL identifier, which
                -- previously raised its own unhandled error and masked this one.
                IF v_head_col IS NOT NULL THEN
                    v_sql := format(
                        'SELECT %I FROM %I.%I WHERE %I = %L AND deleted_at IS NOT NULL',
                        v_pk_col, v_schema, v_table, v_head_col, p_data ->> v_head_col
                    );

                    IF v_parent_ids IS NOT NULL AND v_parent_ids <> '[]' THEN
                        FOR v_parent_key IN
                            SELECT trim(unnest(string_to_array(trim(both '[]' from v_parent_ids), ',')))
                        LOOP
                            v_parent_key := trim(v_parent_key);
                            IF v_parent_key <> '' AND p_data ? v_parent_key THEN
                                v_parent_val := p_data ->> v_parent_key;
                                v_sql := v_sql || format(' AND %I = %L', v_parent_key, v_parent_val);
                            END IF;
                        END LOOP;
                    END IF;

                    v_sql := v_sql || ' LIMIT 1';
                    EXECUTE v_sql INTO v_existing;

                    IF v_existing IS NOT NULL THEN
                        SELECT string_agg(format('%I = %L', key, NULLIF(value #>> '{}', '')), ', ')
                        INTO v_sets
                        FROM jsonb_each(p_data);

                        v_sets := v_sets || ', deleted_at = NULL, deleted_by = NULL';
                        v_sets := v_sets || format(', updated_at = now(), updated_by = %L', p_user);

                        v_sql := format(
                            'UPDATE %I.%I SET %s WHERE %I = %s RETURNING to_jsonb(%I.*)',
                            v_schema, v_table, v_sets, v_pk_col, v_existing, v_table
                        );
                        EXECUTE v_sql INTO v_result;

                        RETURN jsonb_build_object('success', true, 'mode', 'reactivate', 'data', v_result);
                    END IF;
                END IF;

                RETURN jsonb_build_object(
                    'success', false,
                    'error', format('This would duplicate an existing record (violates %s)', coalesce(v_constraint, 'a uniqueness rule'))
                );
            WHEN OTHERS THEN
                RETURN jsonb_build_object('success', false, 'error', SQLERRM);
        END;

        RETURN jsonb_build_object('success', true, 'mode', 'insert', 'data', v_result);
    END IF;

    RETURN jsonb_build_object('success', false, 'error', 'Unexpected state');
END;
$function$
;

