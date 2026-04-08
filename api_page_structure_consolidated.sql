-- Consolidated api_page_structure function
-- Returns page structure with component tree + template references + hydration config
-- n8n workflow handles styling/rendering templates to HTML
-- Includes children recursively (note: currently optimized for 2-level nesting)

CREATE OR REPLACE FUNCTION studio.api_page_structure(p_email CHARACTER VARYING)
RETURNS TABLE(page_structure JSONB) AS $$
WITH page_context AS (
  -- Get page_id from context_store
  SELECT whatsfresh.c_getval(p_email, 'page_id')::INTEGER as page_id
),
page_info AS (
  -- Build pageInfo from page_registry
  SELECT
    jsonb_build_object(
      'pageID', pr.id,
      'appID', pr.app_id,
      'pageName', pr.page_name,
      'pageTitle', pr.table_config->>'pageTitle',
      'tableName', pr.table_config->>'tableName',
      'contextKey', pr.table_config->>'contextKey',
      'status', pr.status
    ) as info
  FROM studio.page_registry pr
  WHERE pr.id = (SELECT page_id FROM page_context)
),
all_components AS (
  -- Get all components with template references + hydration config
  SELECT
    pc.id,
    pc.comp_name,
    pc.parent_id,
    pc.pos_order,
    pc.title,
    pc.html_template_id,
    COALESCE(ht.hydrate::JSONB, '{}'::JSONB) as hydrate
  FROM studio.page_components pc
  LEFT JOIN studio.html_templates ht ON pc.html_template_id = ht.id
  WHERE pc.page_id = (SELECT page_id FROM page_context)
),
components_with_children AS (
  -- Build component objects with nested children
  SELECT
    ac.id,
    ac.comp_name,
    ac.parent_id,
    ac.pos_order,
    ac.title,
    ac.html_template_id,
    ac.hydrate,
    COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'id', child_ac.comp_name,
          'parent_id', child_ac.parent_id,
          'posOrder', child_ac.pos_order,
          'instance_title', child_ac.title,
          'html_template_id', child_ac.html_template_id,
          'hydrate', child_ac.hydrate,
          'children', '[]'::JSONB
        ) ORDER BY child_ac.pos_order
      ),
      '[]'::JSONB
    ) as children_json
  FROM all_components ac
  LEFT JOIN all_components child_ac ON child_ac.parent_id = ac.id
  GROUP BY ac.id, ac.comp_name, ac.parent_id, ac.pos_order, ac.title,
           ac.html_template_id, ac.hydrate
)
SELECT jsonb_build_object(
  'pageInfo', (SELECT info FROM page_info),
  'components', jsonb_agg(
    jsonb_build_object(
      'id', cwc.comp_name,
      'parent_id', cwc.parent_id,
      'posOrder', cwc.pos_order,
      'instance_title', cwc.title,
      'html_template_id', cwc.html_template_id,
      'hydrate', cwc.hydrate,
      'children', cwc.children_json
    ) ORDER BY cwc.pos_order
  ) FILTER (WHERE cwc.parent_id IS NULL)
)::JSONB as page_structure
FROM components_with_children cwc;
$$ LANGUAGE SQL STABLE;
