CREATE OR REPLACE FUNCTION deployment.f_n8n_diff(p_environment text)
 RETURNS TABLE(workflow_name text, dev_content_hash text, target_content_hash text, needs_deploy boolean, detail text)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_env  deployment.environments%ROWTYPE;
    v_conn text := 'n8ndiff_conn_' || p_environment;
BEGIN
    SELECT * INTO v_env FROM deployment.environments WHERE name = p_environment;
    IF v_env.dblink_server IS NULL THEN
        RAISE EXCEPTION 'f_n8n_diff: environment % has no dblink_server configured', p_environment;
    END IF;

    BEGIN
        PERFORM dblink_disconnect(v_conn);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    PERFORM dblink_connect(v_conn, v_env.dblink_server);

    RETURN QUERY
    WITH manifest AS (
        SELECT split_part(o.schema_path, '.', 2) AS wf_name
          FROM knowledge_base.objects o
         WHERE o.platform = 'n8n' AND o.status <> 'obsolete'
    ),
    dev_wf AS (
        -- active=true only: dev has dead workflows sharing a name with a live one.
        -- Content comes from workflow_history at activeVersionId, not
        -- workflow_entity.nodes directly - that column reflects the current DRAFT,
        -- which can differ from what is actually published and live (proven
        -- 2026-08-15: server-query had an unpublished autosave draft diverged
        -- from its activeVersionId content at the time this was built).
        -- credentials stripped per-node before hashing: import-n8n-workflows.sh
        -- deliberately remaps the credential id from dev's to prod's on every
        -- deploy, so that field can never match between environments even for
        -- byte-identical logic - hashing it raw made every DB-touching workflow
        -- read as permanently out of sync. jsonb round-trip (not raw ::text)
        -- also canonicalizes key order/whitespace so those don't cause false
        -- diffs either. Nodes sorted by id since array order isn't guaranteed
        -- to survive an n8n import.
        SELECT w.name::text AS wf_name,
               md5(
                 (SELECT jsonb_agg(elem - 'credentials' ORDER BY elem->>'id')
                    FROM jsonb_array_elements(h.nodes::jsonb) elem)::text
                 || h.connections::jsonb::text
               ) AS content_hash
          FROM public.workflow_entity w
          JOIN manifest m ON m.wf_name = w.name
          JOIN public.workflow_history h ON h."versionId" = w."activeVersionId"
         WHERE w.active = true
    ),
    target_wf AS (
        SELECT * FROM dblink(v_conn,
          'SELECT w.name::text,
                  md5(
                    (SELECT jsonb_agg(elem - ''credentials'' ORDER BY elem->>''id'')
                       FROM jsonb_array_elements(h.nodes::jsonb) elem)::text
                    || h.connections::jsonb::text
                  )
             FROM public.workflow_entity w
             JOIN public.workflow_history h ON h."versionId" = w."activeVersionId"
            WHERE w.active = true') AS t(wf_name text, content_hash text)
         WHERE wf_name IN (SELECT wf_name FROM manifest)
    )
    SELECT m.wf_name,
           d.content_hash,
           t.content_hash,
           CASE WHEN t.wf_name IS NULL THEN true
                WHEN d.content_hash IS DISTINCT FROM t.content_hash THEN true
                ELSE false END,
           CASE WHEN t.wf_name IS NULL THEN 'missing on target'
                WHEN d.content_hash IS DISTINCT FROM t.content_hash THEN 'content differs - needs redeploy'
                ELSE 'in sync' END
    FROM manifest m
    LEFT JOIN dev_wf d ON d.wf_name = m.wf_name
    LEFT JOIN target_wf t ON t.wf_name = m.wf_name
    ORDER BY 4 DESC, m.wf_name;

    PERFORM dblink_disconnect(v_conn);
END;
$function$
;

