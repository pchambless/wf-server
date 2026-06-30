import { actionEngineCode } from './actionEngine.js';
import { actionHandlersCode } from './actionHandlers.js';
import { gridActionsCode } from './gridActions.js';
import { selectActionsCode } from './selectActions.js';
import { formActionsCode } from './formActions.js';
import { reportActionsCode } from './reportActions.js';
import { popActionsCode } from './popActions.js';
import { workerPickerCode } from './workerPicker.js';

export function wrapHtml(title, body) {
  const styleRegex = /<style[^>]*>[\s\S]*?<\/style>/gi;
  const styles = [];

  const fallbackUiStyles = `<style></style>`;

  let match;
  while ((match = styleRegex.exec(body)) !== null) {
    styles.push(match[0]);
  }
  const cleanBody = body.replace(styleRegex, '');

  const inlineScript = `
    (() => {
      ${actionEngineCode}
      ${actionHandlersCode}
      ${gridActionsCode}
      ${selectActionsCode}
      ${formActionsCode}
      ${reportActionsCode}
      ${popActionsCode}
      ${workerPickerCode}

      // Build CRUD buttons dynamically from __pageContext
      document.addEventListener('DOMContentLoaded', () => {
        const ctx = window.__pageContext;
        const container = document.getElementById('crud_buttons');
        if (!container || !ctx?.form || ctx.hideCrud) return;

        const wrapper = document.createElement('div');
        wrapper.className = 'wf-slot-actions wf-context-btn-group';

        const addBtn = document.createElement('button');
        addBtn.type = 'button';
        addBtn.className = 'wf-slot-action-btn';
        addBtn.textContent = 'Add New';
        addBtn.addEventListener('click', () => {
          window.contextStore = { ...(window.contextStore || {}), mode: 'INSERT', [ctx.contextKey]: null };
          const panel = document.getElementById('inline_form_panel');
          const formContainer = document.getElementById('inline_form_container');
          if (!panel || !formContainer) return;
          fetch('/api/hydrate', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ template_name: ctx.form, mode: 'INSERT', ...(window.contextStore || {}) })
          }).then(r => r.text()).then(html => {
            formContainer.innerHTML = html;
            if (window.htmx) window.htmx.process(formContainer);
            const form = formContainer.querySelector('form');
            if (form) form.id = 'inline_form_element';
            const titleEl = document.getElementById('inline_form_title');
            if (titleEl) titleEl.textContent = 'INSERT ' + ctx.form.replace(/_form$/, '').replace(/_/g, ' ');
            panel.classList.remove('hidden');
          });
        });

        const delBtn = document.createElement('button');
        delBtn.type = 'button';
        delBtn.className = 'wf-slot-action-btn wf-btn-danger';
        delBtn.textContent = 'Delete Selected';
        delBtn.addEventListener('click', async () => {
          const pkVal = window.contextStore?.[ctx.contextKey];
          if (!pkVal) { alert('Please select a row to delete'); return; }
          if (!confirm('Delete this record?')) return;
          const response = await fetch('/api/dml', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ page_id: ctx.pageId, mode: 'DELETE', f_id: pkVal })
          });
          const result = await response.json();
          if (result.success) window.location.reload();
          else alert(result.error || 'Delete failed');
        });

        wrapper.appendChild(addBtn);
        wrapper.appendChild(delBtn);
        container.appendChild(wrapper);
      });
    })();
  `;

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${title || 'WhatsFresh'}</title>
  <script src="https://unpkg.com/htmx.org@1.9.10"></script>
  <script>
    // Global loading indicator
    (() => {
      const overlay = document.createElement('div');
      overlay.className = 'wf-loading-overlay';
      overlay.innerHTML = '<div class="wf-spinner"></div>';
      document.addEventListener('DOMContentLoaded', () => document.body.appendChild(overlay));

      let activeRequests = 0;
      const show = () => { activeRequests++; overlay.classList.add('active'); };
      const hide = () => { activeRequests = Math.max(0, activeRequests - 1); if (activeRequests === 0) overlay.classList.remove('active'); };

      const originalFetch = window.fetch;
      window.fetch = function(...args) {
        const url = typeof args[0] === 'string' ? args[0] : args[0]?.url || '';
        if (url.startsWith('/api/')) {
          show();
          return originalFetch.apply(this, args).finally(hide);
        }
        return originalFetch.apply(this, args);
      };

      // Also cover htmx requests
      document.addEventListener('htmx:beforeRequest', show);
      document.addEventListener('htmx:afterRequest', hide);
      document.addEventListener('htmx:responseError', hide);
    })();

    ${inlineScript}
  </script>
  ${fallbackUiStyles}
  ${styles.join('\n')}
</head>
<body>
  ${cleanBody}
</body>
</html>`;
}
