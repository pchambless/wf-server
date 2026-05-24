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

export function getSetVals(step, selectedValue) {
  const vals = step?.payload?.vals || step?.vals || step?.values;
  if (!vals || typeof vals !== 'object' || Array.isArray(vals)) return [];

  return Object.entries(vals)
    .map(([param_name, param_val]) => ({
      param_name,
      param_val: String(resolveActionValue(param_val, selectedValue) ?? '')
    }))
    .filter(({ param_val }) => param_val !== '');
}
