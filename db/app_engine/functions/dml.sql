CREATE OR REPLACE FUNCTION app_engine.dml(p_schema text, p_page_id integer, p_mode text, p_data jsonb DEFAULT NULL::jsonb, p_pk_val integer DEFAULT NULL::integer, p_user text DEFAULT 'system'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_table_raw   text;
    v_table_qual  text;
    v_pk_col      text;
    v_head_col    text;
    v_parent_ids  text;
    v_sql         text;
    v_cols        text;
    v_vals        text;
    v_sets        text;
    v_result      jsonb;
    v_head_val    text;
    v_existing    integer;
    v_constraint  text;
    v_parent_key  text;
BEGIN
    -- table_name/table_id/form_head_col/parent_id are now real columns on
    -- pages (task 345 - promoted out of table_config, which studio.vw_pages
    -- had already proven were the "driving" keys).
    EXECUTE format(
      'SELECT table_name, table_id, form_head_col, parent_id FROM %I.pages WHERE id = $1',
      p_schema
    ) INTO v_table_raw, v_pk_col, v_head_col, v_parent_ids USING p_page_id;

    IF v_table_raw IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', format('Page not found or no table configured: schema=%s page_id=%s', p_schema, p_page_id));
    END IF;

    -- table_name can be schema-qualified (e.g. agile.agile_cache) when a
    -- page's data lives in a different schema than the UI schema (support's
    -- own precedent all session - reaching into agile/deployment/
    -- knowledge_base data from support-owned pages). Quote each part
    -- separately rather than treating the whole string as one identifier.
    IF v_table_raw LIKE '%.%' THEN
        v_table_qual := format('%I.%I', split_part(v_table_raw, '.', 1), split_part(v_table_raw, '.', 2));
    ELSE
        v_table_qual := format('%I.%I', p_schema, v_table_raw);
    END IF;

    IF p_mode NOT IN ('INSERT', 'UPDATE', 'DELETE') THEN
        RETURN jsonb_build_object('success', false, 'error', 'Invalid mode: ' || coalesce(p_mode, 'NULL'));
    END IF;

    IF p_data IS NULL THEN
        p_data := '{}'::jsonb;
    END IF;

    -- Deliberately no c_getval() auto-fill of missing parent columns, and no
    -- whatsfresh.users-style business special case, unlike studio.dml - both are
    -- app-specific concerns (ambient session context, business logic), not core
    -- engine behavior. Caller passes every value explicitly (stateless design).

    IF p_mode = 'DELETE' THEN
        IF p_pk_val IS NULL THEN
            RETURN jsonb_build_object('success', false, 'error', 'DELETE requires p_pk_val');
        END IF;

        v_sql := format(
            'DELETE FROM %s WHERE %I = %s RETURNING to_jsonb(%s.*)',
            v_table_qual, v_pk_col, p_pk_val, v_table_qual
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
                    'UPDATE %s SET deleted_at = now(), deleted_by = %L, updated_at = now() WHERE %I = %s RETURNING to_jsonb(%s.*)',
                    v_table_qual, p_user, v_pk_col, p_pk_val, v_table_qual
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
            'UPDATE %s SET %s WHERE %I = %s RETURNING to_jsonb(%s.*)',
            v_table_qual, v_sets, v_pk_col, p_pk_val, v_table_qual
        );

        BEGIN
            EXECUTE v_sql INTO v_result;
        EXCEPTION WHEN OTHERS THEN
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
                'SELECT %I FROM %s WHERE %I = %L AND deleted_at IS NULL',
                v_pk_col, v_table_qual, v_head_col, v_head_val
            );

            IF v_parent_ids IS NOT NULL AND v_parent_ids <> '[]' THEN
                FOR v_parent_key IN
                    SELECT trim(unnest(string_to_array(trim(both '[]' from v_parent_ids), ',')))
                LOOP
                    v_parent_key := trim(v_parent_key);
                    IF v_parent_key <> '' AND p_data ? v_parent_key THEN
                        v_sql := v_sql || format(' AND %I = %L', v_parent_key, p_data ->> v_parent_key);
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
            'INSERT INTO %s (%s) VALUES (%s) RETURNING to_jsonb(%s.*)',
            v_table_qual, v_cols, v_vals, v_table_qual
        );

        BEGIN
            EXECUTE v_sql INTO v_result;
        EXCEPTION
            WHEN unique_violation THEN
                GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;

                IF v_head_col IS NOT NULL THEN
                    v_sql := format(
                        'SELECT %I FROM %s WHERE %I = %L AND deleted_at IS NOT NULL',
                        v_pk_col, v_table_qual, v_head_col, p_data ->> v_head_col
                    );

                    IF v_parent_ids IS NOT NULL AND v_parent_ids <> '[]' THEN
                        FOR v_parent_key IN
                            SELECT trim(unnest(string_to_array(trim(both '[]' from v_parent_ids), ',')))
                        LOOP
                            v_parent_key := trim(v_parent_key);
                            IF v_parent_key <> '' AND p_data ? v_parent_key THEN
                                v_sql := v_sql || format(' AND %I = %L', v_parent_key, p_data ->> v_parent_key);
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
                            'UPDATE %s SET %s WHERE %I = %s RETURNING to_jsonb(%s.*)',
                            v_table_qual, v_sets, v_pk_col, v_existing, v_table_qual
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

