function escapeHtmlAttr(value) {
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/'/g, '&#39;')
    .replace(/"/g, '&quot;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

export function buildSelectWidget(component, slotAttrs = {}) {
  const { comp_name, template_name } = component;
  let actions = component.actions || {};

  if (typeof actions === 'string') {
    try {
      actions = JSON.parse(actions);
    } catch {
      actions = {};
    }
  }

  const hxVals = { template_name };

  const attrs = [
    `id="${comp_name}"`,
    `data-template-name="${escapeHtmlAttr(template_name)}"`,
    `data-widget="select"`,
    `hx-post="/api/hydrate"`,
    `hx-trigger="load"`,
    `hx-vals='${JSON.stringify(hxVals)}'`,
    `hx-swap="innerHTML"`
  ];

  if (Object.keys(actions).length > 0) {
    attrs.push(`data-actions='${escapeHtmlAttr(JSON.stringify(actions))}'`);
  }

  // Slot attrs: name, data-field, data-selected-value, etc.
  if (slotAttrs && Object.keys(slotAttrs).length > 0) {
    for (const [key, val] of Object.entries(slotAttrs)) {
      attrs.push(`${key}="${escapeHtmlAttr(val)}"`);
    }
  }

  return `<div ${attrs.join(' ')}></div>`;
}
