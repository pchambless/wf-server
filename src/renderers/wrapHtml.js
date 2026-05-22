export function wrapHtml(title, body) {
  const styleRegex = /<style[^>]*>[\s\S]*?<\/style>/gi;
  const styles = [];

  let match;
  while ((match = styleRegex.exec(body)) !== null) {
    styles.push(match[0]);
  }
  const cleanBody = body.replace(styleRegex, '');

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${title || 'WhatsFresh'}</title>
  <script src="https://unpkg.com/htmx.org@1.9.10"></script>
  <script>
    (() => {
      const parseActions = (value) => {
        if (!value) return [];

        try {
          const parsed = JSON.parse(value);
          return Array.isArray(parsed) ? parsed : [];
        } catch {
          return [];
        }
      };

      const getActionValue = (event, wrapper) => {
        const source = event.target instanceof Element ? event.target : null;

        if (source?.matches('select, input, textarea')) {
          return source.value ?? '';
        }

        const field = wrapper.querySelector('select, input, textarea');
        return field?.value ?? '';
      };

      const applySwap = (targetId, html, swapMode) => {
        const target = document.getElementById(targetId);
        if (!target) return;

        if (swapMode === 'outerHTML') {
          target.outerHTML = html;
          const replacement = document.getElementById(targetId);
          if (replacement && window.htmx) window.htmx.process(replacement);
          return;
        }

        target.innerHTML = html;
        if (window.htmx) window.htmx.process(target);
      };

      const getGridRows = (wrapper) => {
        if (!wrapper) return [];

        const explicitRows = Array.from(wrapper.querySelectorAll('.page-grid .grid-row, .table .grid-row'));
        if (explicitRows.length > 0) {
          return explicitRows;
        }

        return Array.from(wrapper.querySelectorAll('.page-grid tbody tr, .table tbody tr'));
      };

      const filterGridRows = (input) => {
        const wrapper = input.closest('[data-template-name]');
        if (!wrapper) return;

        const searchTerm = input.value.trim().toLowerCase();
        const rows = getGridRows(wrapper);

        for (const row of rows) {
          const rowText = row.textContent?.toLowerCase() || '';
          row.style.display = searchTerm === '' || rowText.includes(searchTerm) ? '' : 'none';
        }
      };

      const resolvePlaceholders = (obj, data) => {
        if (typeof obj === 'string') {
          let result = obj;
          for (const [key, val] of Object.entries(data)) {
            const token = '{{' + key + '}}';
            while (result.includes(token)) {
              result = result.replace(token, val ?? '');
            }
          }
          return result;
        }
        if (Array.isArray(obj)) return obj.map(item => resolvePlaceholders(item, data));
        if (obj && typeof obj === 'object') {
          return Object.fromEntries(
            Object.entries(obj).map(([k, v]) => [k, resolvePlaceholders(v, data)])
          );
        }
        return obj;
      };

      const deriveTrigger = (event, source) => {
        if (source?.closest('.grid-row')) return 'row_click';
        if (source?.dataset?.trigger) return source.dataset.trigger;
        const triggerEl = source?.closest('[data-trigger]');
        if (triggerEl) return triggerEl.dataset.trigger;
        if (source?.matches('select')) return 'select_change';
        if (source?.matches('input, textarea')) return 'input';
        if (event.type === 'submit') return 'submit';
        return 'click';
      };

      const handleActionEvent = async (event) => {
        const source = event.target instanceof Element ? event.target : null;
        const wrapper = source?.closest('[data-actions]');
        if (!wrapper) return;

        const trigger = deriveTrigger(event, source);
        const actions = parseActions(wrapper.dataset.actions);
        let action = actions.find(candidate => candidate.trigger === trigger);
        if (!action) return;

        const gridRow = source?.closest('.grid-row');
        if (gridRow) {
          const rowData = { id: gridRow.dataset.rowId, ...gridRow.dataset };
          action = resolvePlaceholders(action, rowData);
        }

        if (event.type === 'submit') {
          event.preventDefault();
        }

        const response = await fetch('/api/actions', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json'
          },
          body: JSON.stringify({
            component_id: wrapper.id,
            template_name: wrapper.dataset.templateName,
            value: getActionValue(event, wrapper),
            action
          })
        });

        if (!response.ok) {
          return;
        }

        const result = await response.json();

        if (result?.redirectUrl) {
          window.location.href = result.redirectUrl;
          return;
        }

        const updates = Array.isArray(result?.updates) ? result.updates : [];

        for (const update of updates) {
          applySwap(update.target, update.html, update.swapMode);
        }
      };

      for (const eventName of ['change', 'click', 'input', 'submit']) {
        document.addEventListener(eventName, handleActionEvent);
      }

      document.addEventListener('input', function(event) {
        const target = event.target instanceof HTMLInputElement ? event.target : null;
        if (!target?.matches('.grid-search .search-input, .grid-search input[type="search"], .grid-search input[type="text"]')) {
          return;
        }

        filterGridRows(target);
      });

      const closeDropdownMenus = () => {
        document.querySelectorAll('.dropdown-menu.open').forEach(function(menu) {
          menu.classList.remove('open');
        });
        document.querySelectorAll('.dropdown-toggle.open').forEach(function(toggle) {
          toggle.classList.remove('open');
        });
      };

      // Dropdown menu toggle handler
      document.addEventListener('click', function(e) {
        const toggle = e.target.closest('.dropdown-toggle');
        if (toggle) {
          e.preventDefault();
          const dropdownId = toggle.getAttribute('data-dropdown');
          const menu = dropdownId ? document.getElementById(dropdownId) : null;
          if (!menu) return;

          const shouldOpen = !menu.classList.contains('open');
          closeDropdownMenus();

          if (shouldOpen) {
            menu.classList.add('open');
            toggle.classList.add('open');
          }
          return;
        }

        if (e.target.closest('.dropdown-menu a')) {
          closeDropdownMenus();
          return;
        }

        if (!e.target.closest('.nav-item')) {
          closeDropdownMenus();
        }
      });
    })();
  </script>
  ${styles.join('\n')}
</head>
<body>
  ${cleanBody}
</body>
</html>`;
}
