const TRIGGER_MAP = {
  'select_change': 'change',
  'click': 'click',
  'submit': 'submit',
  'input': 'input'
};

const ACTION_ENDPOINT = {
  'setVals': '/api/setvals',
  'clearVals': '/api/clearvals',
  'hydrate': '/api/hydrate'
};

export function buildHtmxDiv(component) {
  const { comp_name, template_name, actions = [] } = component;

  const attrs = [
    `id="${comp_name}"`,
    `hx-post="/api/hydrate"`,
    `hx-trigger="load"`,
    `hx-vals='${JSON.stringify({ template_name })}'`,
    `hx-swap="innerHTML"`
  ];

  for (const action of actions) {
    const trigger = TRIGGER_MAP[action.trigger] || action.trigger;
    const endpoint = ACTION_ENDPOINT[action.actions?.[0]] || '/api/hydrate';
    const targets = (action.targets || []).map(t => `#${t}`).join(', ');

    if (trigger && trigger !== 'load') {
      attrs.push(`data-action-trigger="${trigger}"`);
      attrs.push(`data-action-endpoint="${endpoint}"`);
      if (targets) attrs.push(`data-action-targets="${targets}"`);
      if (action.swap_mode && action.swap_mode !== 'none') {
        attrs.push(`data-action-swap="${action.swap_mode}"`);
      }
      if (action.payload) {
        attrs.push(`data-action-payload='${JSON.stringify(action.payload)}'`);
      }
    }
  }

  return `<div ${attrs.join('\n     ')}>\n  </div>`;
}
