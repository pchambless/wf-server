CREATE OR REPLACE FUNCTION whatsfresh.dml(p_table text, p_mode text, p_data jsonb, p_pk_val integer DEFAULT NULL::integer, p_user text DEFAULT 'system'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_sql       text;
    v_cols      text;
    v_vals      text;
    v_sets      text;
    v_result    jsonb;
    v_key       text;
    v_keys      text[];
    v_name_val  text;
    v_existing  integer;
BEGIN
    -- Validate mode
    IF p_mode NOT IN ('INSERT', 'UPDATE', 'DELETE') THEN
        RETURN jsonb_build_object('success', false, 'error', 'Invalid mode: ' || p_mode);
    END IF;

    -- Validate table exists in whatsfresh schema
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'whatsfresh' AND table_name = p_table
    ) THEN
        RETURN jsonb_build_object('success', false, 'error', 'Table not found: ' || p_table);
    END IF;

    -- ===================
    -- DELETE (hard-delete first, soft-delete on FK violation)
    -- ===================
    IF p_mode = 'DELETE' THEN
        IF p_pk_val IS NULL THEN
            RETURN jsonb_build_object('success', false, 'error', 'DELETE requires p_pk_val');
        END IF;

        -- Try hard-delete first
        v_sql := format(
            'DELETE FROM whatsfresh.%I WHERE id = %s RETURNING to_jsonb(%I.*)',
            p_table, p_pk_val, p_table
        );
        BEGIN
            EXECUTE v_sql INTO v_result;

            IF v_result IS NULL THEN
                RETURN jsonb_build_object('success', false, 'error', 'Row not found: id=' || p_pk_val);
            END IF;

            RETURN jsonb_build_object('success', true, 'mode', 'hard-delete', 'data', v_result);
        EXCEPTION
            WHEN foreign_key_violation THEN
                -- FK constraint blocks hard-delete, fall back to soft-delete
                v_sql := format(
                    'UPDATE whatsfresh.%I SET deleted_at = now(), deleted_by = %L, updated_at = now() WHERE id = %s RETURNING to_jsonb(%I.*)',
                    p_table, p_user, p_pk_val, p_table
                );
                EXECUTE v_sql INTO v_result;

                IF v_result IS NULL THEN
                    RETURN jsonb_build_object('success', false, 'error', 'Row not found: id=' || p_pk_val);
                END IF;

                RETURN jsonb_build_object('success', true, 'mode', 'soft-delete', 'data', v_result);
        END;
    END IF;

    -- ===================
    -- UPDATE
    -- ===================
    IF p_mode = 'UPDATE' THEN
        IF p_pk_val IS NULL THEN
            RETURN jsonb_build_object('success', false, 'error', 'UPDATE requires p_pk_val');
        END IF;

        -- Build SET clause from p_data keys
        SELECT string_agg(format('%I = %L', key, value #>> '{}'), ', ')
        INTO v_sets
        FROM jsonb_each(p_data);

        IF v_sets IS NULL OR v_sets = '' THEN
            RETURN jsonb_build_object('success', false, 'error', 'No fields to update');
        END IF;

        -- Append audit fields
        v_sets := v_sets || format(', updated_at = now(), updated_by = %L', p_user);

        v_sql := format(
            'UPDATE whatsfresh.%I SET %s WHERE id = %s RETURNING to_jsonb(%I.*)',
            p_table, v_sets, p_pk_val, p_table
        );
        EXECUTE v_sql INTO v_result;

        IF v_result IS NULL THEN
            RETURN jsonb_build_object('success', false, 'error', 'Row not found: id=' || p_pk_val);
        END IF;

        RETURN jsonb_build_object('success', true, 'data', v_result);
    END IF;

    -- ===================
    -- INSERT
    -- ===================
    IF p_mode = 'INSERT' THEN

        -- Pre-check: if p_data has 'name', check for existing active row
        IF p_data ? 'name' THEN
            v_name_val := p_data ->> 'name';

            -- Default check on name alone
            v_sql := format(
                'SELECT id FROM whatsfresh.%I WHERE name = %L AND deleted_at IS NULL LIMIT 1',
                p_table, v_name_val
            );
            -- Add account_id filter if present in data
            IF p_data ? 'account_id' THEN
                v_sql := format(
                    'SELECT id FROM whatsfresh.%I WHERE account_id = %s AND name = %L AND deleted_at IS NULL LIMIT 1',
                    p_table, (p_data ->> 'account_id')::integer, v_name_val
                );
            END IF;

            EXECUTE v_sql INTO v_existing;

            IF v_existing IS NOT NULL THEN
                RETURN jsonb_build_object(
                    'success', false,
                    'error', format('Name ''%s'' already exists (id=%s)', v_name_val, v_existing)
                );
            END IF;
        END IF;

        -- Build INSERT from p_data keys + audit fields
        SELECT
            string_agg(format('%I', key), ', '),
            string_agg(format('%L', value #>> '{}'), ', ')
        INTO v_cols, v_vals
        FROM jsonb_each(p_data);

        -- Append audit columns
        v_cols := v_cols || ', created_at, created_by';
        v_vals := v_vals || format(', now(), %L', p_user);

        v_sql := format(
            'INSERT INTO whatsfresh.%I (%s) VALUES (%s) RETURNING to_jsonb(%I.*)',
            p_table, v_cols, v_vals, p_table
        );

        BEGIN
            EXECUTE v_sql INTO v_result;
        EXCEPTION
            WHEN unique_violation THEN
                RETURN jsonb_build_object(
                    'success', false,
                    'error', format('Duplicate entry for %s', p_table)
                );
        END;

        RETURN jsonb_build_object('success', true, 'data', v_result);
    END IF;

END;
$function$
;

