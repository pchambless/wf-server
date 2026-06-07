function escapeHtmlAttr(value) {
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/'/g, '&#39;')
    .replace(/"/g, '&quot;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

export function buildFormSelect(component, slotAttrs = {}) {
  const { comp_name, template_name, template_title } = component;
  let actions = component.actions || {};

  if (typeof actions === 'string') {
    try {
      actions = JSON.parse(actions);
    } catch {
      actions = {};
    }
  }

  // For form selects, include all slotAttrs as HTMX values
  // These contain the form data (f_measure_id, f_location_id, etc.)
  const hxVals = {
    template_name,
    ...slotAttrs
  };

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

  if (slotAttrs && Object.keys(slotAttrs).length > 0) {
    for (const [key, val] of Object.entries(slotAttrs)) {
      attrs.push(`${key}="${escapeHtmlAttr(val)}"`);
    }
  }

  if (!template_title) {
    throw new Error(`Form select widget "${template_name}" missing required template_title for label`);
  }

  return `<div class="dropdown-label">${escapeHtmlAttr(template_title)}</div><div ${attrs.join(' ')}></div>`;
}
