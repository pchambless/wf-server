const TRIGGER_MAP = {
  'select_change': 'change',
  'click': 'click',
  'submit': 'submit',
  'input': 'input'
};

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

function normalizeActionSteps(action) {
  if (Array.isArray(action.actions) && action.actions.length > 0) {
    return action.actions;
  }

  if (!action.action) {
    return [];
  }

  const normalized = [{
    action: action.action,
    values: action.values,
    payload: action.payload || {}
  }];

  if (normalizeTargets(action.targets).length > 0) {
    normalized.push({
      action: 'hydrate',
      targets: action.targets
    });
  }

  return normalized;
}

export function buildHtmxDiv(component) {
  const { comp_name, template_name } = component;
  let actions = component.actions || [];

  if (typeof actions === 'string') {
    try {
      actions = JSON.parse(actions);
    } catch {
      actions = [];
    }
  }

  if (!Array.isArray(actions)) {
    actions = [];
  }

  const normalizedActions = actions
    .map(action => ({
      trigger: TRIGGER_MAP[action.trigger] || action.trigger,
      actions: normalizeActionSteps(action),
      swap_mode: action.swap_mode,
      targets: normalizeTargets(action.targets),
      payload: action.payload || {}
    }))
    .filter(action => action.trigger);

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

  if (normalizedActions.length > 0) {
    attrs.push(`data-actions='${escapeHtmlAttr(JSON.stringify(normalizedActions))}'`);
  }

  return `<div ${attrs.join('\n     ')}>\n  </div>`;
}
