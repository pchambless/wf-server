export function buildCrudButtons(pageInfo) {
  if (pageInfo.templateType !== 'crud') return '';

  const contextKey = pageInfo.contextKey || 'id';
  const formTemplate = pageInfo.formTemplate;
  const gridTemplate = pageInfo.gridTemplate;

  if (!formTemplate && !gridTemplate) return '';

  const actions = {};

  if (formTemplate) {
    actions.add_new = {
      action: 'open_modal',
      form_template: formTemplate,
      values: { mode: 'INSERT' },
      targets: ['form_modal']
    };
  }

  if (gridTemplate) {
    actions.delete_selected = {
      action: 'row_delete',
      values: { mode: 'DELETE' },
      targets: [gridTemplate]
    };
  }

  const escapeAttr = (str) => String(str)
    .replace(/&/g, '&amp;')
    .replace(/'/g, '&#39;')
    .replace(/"/g, '&quot;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');

  const buttons = [];
  if (formTemplate) {
    buttons.push('<button type="button" data-trigger="add_new" class="wf-slot-action-btn">Add New</button>');
  }
  if (gridTemplate) {
    buttons.push('<button type="button" data-trigger="delete_selected" class="wf-slot-action-btn wf-btn-danger">Delete Selected</button>');
  }

  return `<div class="wf-slot-actions" data-actions='${escapeAttr(JSON.stringify(actions))}'>${buttons.join('')}</div>`;
}
