CREATE OR REPLACE FUNCTION deployment.f_capture_change(p_task_id integer, p_schema text, p_object text, p_component text DEFAULT NULL::text, p_note text DEFAULT NULL::text, p_by text DEFAULT 'claude'::text)
 RETURNS TABLE(item_type text, schema_name text, object_name text, component_name text, status text, description text, action text)
 LANGUAGE plpgsql
AS $function$
-- Task 583. Call right after changing a DB object: logs the impact on p_task_id now, while the why is known.
-- p_object matches the object name, or a function name without its argument list. p_component narrows
-- (a studio row id, an n8n node name). p_note (max 256 bytes) is the description; default is the change type.
-- One impact row per (task, item_type, schema, object, component): a second edit updates it, and an object
-- added in this task stays 'A'. Sets object_state.captured_fingerprint so f_capture_impacts will not log it again.
DECLARE
    r        record;
    v_id     integer;
    v_old    text;
    v_status text;
    v_desc   text;
    v_n      integer := 0;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM agile.agile_cache WHERE id = p_task_id) THEN
        RAISE EXCEPTION 'f_capture_change: task % does not exist', p_task_id;
    END IF;

    PERFORM deployment.f_scan();

    FOR r IN
        SELECT d.kind, d.schema_name AS sch, d.object_name AS obj, d.component_name AS comp,
               d.change_type, d.detail, s.id AS sid, s.fingerprint
          FROM deployment.vw_object_drift d
          JOIN deployment.object_state s
            ON s.kind = d.kind AND s.schema_name = d.schema_name AND s.object_name = d.object_name
           AND s.component_name = COALESCE(d.component_name, '')
         WHERE d.schema_name = p_schema
           AND (d.object_name = p_object OR split_part(d.object_name, '(', 1) = p_object)
           AND (p_component IS NULL OR d.component_name = p_component)
           AND s.captured_fingerprint IS DISTINCT FROM s.fingerprint
         ORDER BY d.kind, d.object_name, d.component_name
    LOOP
        v_status := deployment.f_impact_status(r.change_type);
        v_desc   := left(COALESCE(NULLIF(p_note, ''), r.detail), 256);
        -- left() counts characters; the column check counts bytes
        WHILE octet_length(v_desc) > 256 LOOP v_desc := left(v_desc, length(v_desc) - 1); END LOOP;

        SELECT i.id, i.status INTO v_id, v_old
          FROM agile.agile_impacts i
         WHERE i.task_id = p_task_id AND i.item_type = deployment.f_impact_item_type(r.kind)
           AND i.schema_name = r.sch AND i.object_name = r.obj
           AND COALESCE(i.component_name, '') = COALESCE(r.comp, '')
         ORDER BY i.id DESC LIMIT 1;

        IF v_id IS NULL THEN
            INSERT INTO agile.agile_impacts (task_id, item_type, schema_name, object_name, component_name, status, description, created_by)
            VALUES (p_task_id, deployment.f_impact_item_type(r.kind), r.sch, r.obj, NULLIF(r.comp, ''), v_status, v_desc, p_by);
            action := 'logged';
        ELSE
            UPDATE agile.agile_impacts
               SET status = CASE WHEN v_old = 'A' AND v_status = 'M' THEN 'A' ELSE v_status END,
                   description = v_desc
             WHERE id = v_id;
            action := 'updated';
        END IF;

        UPDATE deployment.object_state SET captured_fingerprint = r.fingerprint WHERE id = r.sid;

        item_type := deployment.f_impact_item_type(r.kind); schema_name := r.sch; object_name := r.obj;
        component_name := NULLIF(r.comp, ''); status := v_status; description := v_desc;
        v_n := v_n + 1;
        RETURN NEXT;
    END LOOP;

    IF v_n = 0 THEN
        item_type := NULL; schema_name := p_schema; object_name := p_object; component_name := p_component;
        status := NULL; description := 'no uncaptured change found (not fingerprinted, unchanged, or already captured)';
        action := 'no-change';
        RETURN NEXT;
    END IF;
END;
$function$
;

