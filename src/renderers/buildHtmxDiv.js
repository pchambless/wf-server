function normalizeTargets(targets) {
  if (Array.isArray(targets)) return targets;
  if (typeof targets !== 'string' || targets.trim() === '') return [];

  try {
    const parsed = JSON.parse(targets);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [targets];
  }
}

function escapeHtmlAttr(value) {
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/'/g, '&#39;')
    .replace(/"/g, '&quot;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

export function buildHtmxDiv(component) {
  const { comp_name, template_name } = component;
  let actions = component.actions || [];

  if (typeof actions === 'string') {
    try {
      actions = JSON.parse(actions);
    } catch {
      actions = {};
    }
  }

  if (!actions || typeof actions !== 'object') {
    actions = {};
  }

  // Actions are now trigger-keyed objects: { trigger_name: action_or_actions_array, ... }
  // Pass them directly as-is
  const normalizedActions = actions;

  const hxVals = { template_name };
  if (component.page_id !== undefined && component.page_id !== null) {
    hxVals.page_id = component.page_id;
  }
  if (component.page_title !== undefined && component.page_title !== null) {
    hxVals.page_title = component.page_title;
  }

  const attrs = [
    `id="${comp_name}"`,
    `data-template-name="${escapeHtmlAttr(template_name)}"`,
    `hx-post="/api/hydrate"`,
    `hx-trigger="load"`,
    `hx-vals='${JSON.stringify(hxVals)}'`,
    `hx-swap="innerHTML"`
  ];

  if (Object.keys(normalizedActions).length > 0) {
    attrs.push(`data-actions='${escapeHtmlAttr(JSON.stringify(normalizedActions))}'`);
  }

  return `<div ${attrs.join('\n     ')}>\n  </div>`;
}
