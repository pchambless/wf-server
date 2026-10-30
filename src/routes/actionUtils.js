export function parseAction(action) {
  if (!action) return null;

  if (typeof action === 'string') {
    try {
      return JSON.parse(action);
    } catch {
      return null;
    }
  }

  return action;
}

export function normalizeTargets(targets) {
  if (Array.isArray(targets)) return targets.filter(Boolean);
  if (typeof targets !== 'string' || targets.trim() === '') return [];

  try {
    const parsed = JSON.parse(targets);
    return Array.isArray(parsed) ? parsed.filter(Boolean) : [];
  } catch {
    return [targets];
  }
}

function resolveActionValue(value, selectedValue) {
  if (typeof value === 'string') {
    return value
      .replaceAll('{{value}}', selectedValue ?? '')
      .replaceAll('{{selected_value}}', selectedValue ?? '');
  }

  if (Array.isArray(value)) {
    return value.map(item => resolveActionValue(item, selectedValue));
  }

  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.entries(value).map(([key, entryValue]) => [key, resolveActionValue(entryValue, selectedValue)])
    );
  }

  return value;
}

// Context keys are plain identifiers (account_id, product_type_id, mode, ...). The browser
// supplies the action definition, so anything else is dropped before it reaches n8n.
const CONTEXT_KEY = /^[A-Za-z][A-Za-z0-9_]{0,63}$/;

export function isContextKey(name) {
  return typeof name === 'string' && CONTEXT_KEY.test(name);
}

export function getSetVals(step, selectedValue) {
  const vals = step?.payload?.vals || step?.vals || step?.values;
  if (!vals || typeof vals !== 'object' || Array.isArray(vals)) return [];

  return Object.entries(vals)
    .filter(([param_name]) => isContextKey(param_name))
    .map(([param_name, param_val]) => ({
      param_name,
      param_val: String(resolveActionValue(param_val, selectedValue) ?? '')
    }))
    .filter(({ param_val }) => param_val !== '');
}
