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
    v_email         text;
    v_caller_id     integer;
    v_caller_role   integer;
    v_row_account   integer;
    v_new_account   integer;
    v_caller_email  text;
    v_target_account integer;
    v_has_acct      boolean;
    v_ref           text;
    v_ref_acct      integer;
    v_cur           text;
    v_kv            record;
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

    -- The caller is the email wf-server sends as p_user (session identity, Task 837 / hotfix 867); the
    -- app.current_email setting is only a fallback for callers that pass no email.
    v_caller_email := CASE WHEN p_user LIKE '%@%' THEN p_user ELSE nullif(current_setting('app.current_email', true), '') END;

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
    -- Task 839: users, accounts and accounts_users carry permission data, so writes to them are
    -- gated by the caller's role, keyed on the target TABLE (pages 12, 14 and 38 all point at
    -- whatsfresh.users). The caller is the email the dml webhook set for this call, never p_user
    -- (which is replaced by the first name above). No resolvable caller: refuse, fail closed.
    --   users, accounts : role 1 only. Passwords never come through UPDATE (change-password only).
    --   accounts_users  : role 1, or an owner of the row's account AND of the account being written.
    -- Other tables are not touched by this block.
    -- ===================
    IF v_schema = 'whatsfresh' AND v_table IN ('users', 'accounts', 'accounts_users') THEN
        v_email := v_caller_email;

        SELECT u.id, u.role INTO v_caller_id, v_caller_role
          FROM whatsfresh.users u
         WHERE lower(u.email) = lower(v_email) AND u.deleted_at IS NULL
         LIMIT 1;

        IF v_caller_id IS NULL THEN
            RETURN jsonb_build_object('success', false, 'error', 'Not allowed');
        END IF;

        -- A request never supplies the key or the creation stamp. deleted_at/deleted_by stay: the
        -- grids' Active checkbox deactivates a row by sending them, and the role checks below
        -- already decide who may change these rows.
        SELECT coalesce(jsonb_object_agg(key, value), '{}'::jsonb) INTO p_data
          FROM jsonb_each(p_data)
         WHERE key !~ '^(id|created_.*)\Z';

        IF v_table IN ('users', 'accounts') THEN
            IF v_caller_role IS DISTINCT FROM 1 THEN
                RETURN jsonb_build_object('success', false, 'error', 'Not allowed');
            END IF;

            IF v_table = 'users' AND p_mode = 'UPDATE'
               AND (p_data ? 'password' OR p_data ? 'confirm_password') THEN
                RETURN jsonb_build_object('success', false, 'error', 'Passwords change only through change-password');
            END IF;
        ELSIF v_caller_role IS DISTINCT FROM 1 THEN
            IF p_mode IN ('UPDATE', 'DELETE') THEN
                SELECT au.account_id INTO v_row_account
                  FROM whatsfresh.accounts_users au
                 WHERE au.id = p_pk_val;

                IF v_row_account IS NULL OR NOT EXISTS (
                    SELECT 1 FROM whatsfresh.accounts_users o
                     WHERE o.user_id = v_caller_id AND o.account_id = v_row_account
                       AND o.is_owner = 1 AND o.deleted_at IS NULL) THEN
                    RETURN jsonb_build_object('success', false, 'error', format('Row not found: %s=%s', v_pk_col, p_pk_val));
                END IF;
            END IF;

            IF p_mode = 'INSERT' OR (p_mode = 'UPDATE' AND p_data ? 'account_id') THEN
                IF coalesce(p_data ->> 'account_id', '') !~ '^[0-9]+\Z' THEN
                    RETURN jsonb_build_object('success', false, 'error', 'Not allowed');
                END IF;
                v_new_account := (p_data ->> 'account_id')::integer;

                IF NOT EXISTS (
                    SELECT 1 FROM whatsfresh.accounts_users o
                     WHERE o.user_id = v_caller_id AND o.account_id = v_new_account
                       AND o.is_owner = 1 AND o.deleted_at IS NULL) THEN
                    RETURN jsonb_build_object('success', false, 'error', 'Not allowed');
                END IF;
            END IF;
        END IF;
    END IF;


    -- ===================
    -- Task 837: account ownership for every other whatsfresh table. The caller is the email wf-server sent
    -- (v_caller_email); the account is checked with whatsfresh.f_can_access_account (role 1, or a live member).
    --   UPDATE/DELETE: the row's own account (studio.f_dml_row_account) must be accessible, else "Row not found"
    --                  (does not reveal that the row exists). account_id is never changed by an UPDATE.
    --   INSERT:        account_id is forced from the caller's context (never taken from the request); the two
    --                  tables without one take the account of their product or batch. It must be accessible.
    --   References:    every id the request sets (studio.f_dml_ref_table) must point at a row of the same account
    --                  or a shared one (account 0). On UPDATE an unchanged value is left alone (legacy rows).
    -- The soft-delete, fallback and reactivate paths below act only on rows that passed these checks.
    -- ===================
    IF v_schema = 'whatsfresh' AND v_table NOT IN ('users', 'accounts', 'accounts_users') THEN
        SELECT u.id, u.role INTO v_caller_id, v_caller_role
          FROM whatsfresh.users u
         WHERE lower(u.email) = lower(v_caller_email) AND u.deleted_at IS NULL
         LIMIT 1;

        IF v_caller_id IS NULL THEN
            RETURN jsonb_build_object('success', false, 'error', 'Not allowed');
        END IF;

        -- A request never supplies the key or the creation stamp.
        SELECT coalesce(jsonb_object_agg(key, value), '{}'::jsonb) INTO p_data
          FROM jsonb_each(p_data)
         WHERE key !~ '^(id|created_.*)\Z';

        v_has_acct := EXISTS (SELECT 1 FROM information_schema.columns c
                               WHERE c.table_schema = v_schema AND c.table_name = v_table AND c.column_name = 'account_id');

        IF p_mode IN ('UPDATE', 'DELETE') THEN
            v_target_account := studio.f_dml_row_account(v_table, p_pk_val);

            IF v_target_account IS NULL OR NOT whatsfresh.f_can_access_account(v_caller_email, v_target_account) THEN
                RETURN jsonb_build_object('success', false, 'error', format('Row not found: %s=%s', v_pk_col, p_pk_val));
            END IF;

            IF v_has_acct THEN
                p_data := p_data - 'account_id';
            END IF;
        ELSE
            IF v_has_acct THEN
                -- Same source as c_getval('account_id'), read for the caller explicitly.
                SELECT coalesce(nullif(cs.context ->> 'account_id', ''), (SELECT u.default_account_id::text FROM whatsfresh.users u WHERE u.id = v_caller_id))
                  INTO v_ref
                  FROM whatsfresh.api_context_store(v_caller_email) cs;
                v_ref := coalesce(v_ref, (SELECT u.default_account_id::text FROM whatsfresh.users u WHERE u.id = v_caller_id));
                v_target_account := CASE WHEN v_ref ~ '^[0-9]+\Z' THEN v_ref::integer END;

                IF v_target_account IS NOT NULL THEN
                    p_data := p_data || jsonb_build_object('account_id', v_target_account);
                END IF;
            ELSIF v_table = 'product_recipes' THEN
                v_target_account := CASE WHEN p_data ->> 'product_id' ~ '^[0-9]+\Z'
                                         THEN studio.f_dml_row_account('entities', (p_data ->> 'product_id')::integer) END;
            ELSIF v_table = 'product_batch_tasks' THEN
                v_target_account := CASE WHEN p_data ->> 'batch_id' ~ '^[0-9]+\Z'
                                         THEN studio.f_dml_row_account('batches', (p_data ->> 'batch_id')::integer) END;
            END IF;

            IF v_target_account IS NULL OR NOT whatsfresh.f_can_access_account(v_caller_email, v_target_account) THEN
                RETURN jsonb_build_object('success', false, 'error', 'Not allowed');
            END IF;
        END IF;

        IF p_mode IN ('INSERT', 'UPDATE') THEN
            FOR v_kv IN SELECT key, value #>> '{}' AS val FROM jsonb_each(p_data) LOOP
                v_ref := studio.f_dml_ref_table(v_table, v_kv.key);
                CONTINUE WHEN v_ref IS NULL OR nullif(v_kv.val, '') IS NULL;

                IF v_kv.val !~ '^[0-9]+\Z' THEN
                    RETURN jsonb_build_object('success', false, 'error', 'Not allowed');
                END IF;

                IF p_mode = 'UPDATE' THEN
                    EXECUTE format('SELECT %I::text FROM %I.%I WHERE %I = $1', v_kv.key, v_schema, v_table, v_pk_col)
                       INTO v_cur USING p_pk_val;
                    CONTINUE WHEN v_cur IS NOT DISTINCT FROM v_kv.val;
                END IF;

                v_ref_acct := studio.f_dml_row_account(v_ref, v_kv.val::integer);
                IF v_ref_acct IS NULL OR v_ref_acct NOT IN (v_target_account, 0) THEN
                    RETURN jsonb_build_object('success', false, 'error', 'Not allowed');
                END IF;
            END LOOP;
        END IF;
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
            2,  -- Add User always creates a role-2 user; an admin promotes later on the Users page (task 839)
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

        -- History that depends on a row without a foreign key (e.g. a recipe row used by batches):
        -- deactivate, never hard-delete (task 622). whatsfresh.f_row_in_use lists the tables affected.
        IF v_schema = 'whatsfresh' AND whatsfresh.f_row_in_use(v_table, p_pk_val) THEN
            v_sql := format(
                'UPDATE %I.%I SET deleted_at = now(), deleted_by = %L, updated_at = now() WHERE %I = %s RETURNING to_jsonb(%I.*)',
                v_schema, v_table, p_user, v_pk_col, p_pk_val, v_table
            );
            EXECUTE v_sql INTO v_result;

            IF v_result IS NULL THEN
                RETURN jsonb_build_object('success', false, 'error', format('Row not found: %s=%s', v_pk_col, p_pk_val));
            END IF;

            RETURN jsonb_build_object('success', true, 'mode', 'soft-delete', 'data', v_result);
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

                    -- Task 837: only revive a row of the account this INSERT is for.
                    IF v_existing IS NOT NULL
                       AND (v_target_account IS NULL OR studio.f_dml_row_account(v_table, v_existing) IS NOT DISTINCT FROM v_target_account) THEN
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

