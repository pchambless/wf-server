import { callWorkflow } from '../utils/n8nClient.js';

export function normalizeHtml(result) {
  if (!result) return '';

  if (typeof result === 'string') {
    return result;
  }

  if (Array.isArray(result)) {
    for (const item of result) {
      const html = normalizeHtml(item);
      if (html) return html;
    }
    return '';
  }

  if (typeof result === 'object') {
    if (typeof result.html === 'string' && result.html.length > 0) {
      return result.html;
    }

    // Common n8n wrapper shapes
    if (result.data) {
      const htmlFromData = normalizeHtml(result.data);
      if (htmlFromData) return htmlFromData;
    }
    if (result.body) {
      const htmlFromBody = normalizeHtml(result.body);
      if (htmlFromBody) return htmlFromBody;
    }
    if (result.result) {
      const htmlFromResult = normalizeHtml(result.result);
      if (htmlFromResult) return htmlFromResult;
    }
    if (result.output) {
      const htmlFromOutput = normalizeHtml(result.output);
      if (htmlFromOutput) return htmlFromOutput;
    }
  }

  return '';
}

function escapeRegExp(value) {
  return String(value).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

export function applySelectedAccount(html, accountId) {
  if (!html || accountId === null || accountId === undefined || accountId === '') {
    return html;
  }

  if (/\sselected(?:=|\s|>)/i.test(html)) {
    return html;
  }

  const value = escapeRegExp(String(accountId));
  const optionPattern = new RegExp(`(<option\\b[^>]*value=["'])${value}(["'][^>]*)(>)`, 'i');

  if (!optionPattern.test(html)) {
    return html;
  }

  return html.replace(optionPattern, '$1' + String(accountId) + '$2 selected$3');
}

export async function hydrateTargets(email, targets, swapMode) {
  if (targets.length === 0) return [];

  const structure = await callWorkflow('page-structure', { email });
  const pageInfo = structure?.pageInfo;
  const components = Array.isArray(structure?.components) ? structure.components : [];
  const componentByName = new Map(components.map(component => [component.comp_name, component]));
  const updates = [];

  for (const target of targets) {
    const component = target === 'appbar'
      ? {
          comp_name: 'appbar',
          template_name: 'wf_appbar',
          page_id: pageInfo?.pageID,
          page_title: pageInfo?.pageTitle
        }
      : componentByName.get(target);
    if (!component?.template_name) continue;

    const workflowName = component.template_name === 'wf_appbar' ? 'page-chrome' : 'hydrate-guide';
    const result = await callWorkflow(workflowName, {
      ...(component.template_name === 'wf_appbar'
        ? {
            ...(email ? { email } : {}),
            ...(component.page_id ? { page_id: component.page_id } : {}),
            ...(component.page_title ? { page_title: component.page_title } : {})
          }
        : {
            template_name: component.template_name,
            source: 'wf-server',
            format: 'html',
            ...(email ? { email } : {})
          })
    });

    updates.push({
      target,
      html: normalizeHtml(result),
      swapMode: swapMode || 'innerHTML'
    });
  }

  return updates;
}
