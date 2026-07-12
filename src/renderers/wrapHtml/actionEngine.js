export const actionEngineCode = `
      const parseActions = (value) => {
        if (!value) return {};
        try {
          const parsed = JSON.parse(value);
          return typeof parsed === 'object' ? parsed : {};
        } catch {
          return {};
        }
      };

      const getActionValue = (event, wrapper) => {
        const source = event.target instanceof Element
          ? event.target
          : event.target?.parentElement || null;
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

      const toFieldKey = (label) => {
        return String(label || '')
          .trim()
          .toLowerCase()
          .replace(/[^a-z0-9]+/g, '_')
          .replace(/^_+|_+$/g, '');
      };

      const deriveGridRowData = (gridRow) => {
        if (!gridRow) return {};
        const rawDataset = { ...gridRow.dataset };
        const rowData = {};
        for (const [key, val] of Object.entries(rawDataset)) {
          rowData[key] = val;
          const snakeKey = key.replace(/([A-Z])/g, '_$1').toLowerCase();
          if (snakeKey !== key) rowData[snakeKey] = val;
        }
        if (rawDataset.rowId !== undefined) {
          rowData.id = rawDataset.rowId;
        }
        const table = gridRow.closest('table');
        const headerCells = table ? Array.from(table.querySelectorAll('thead th')) : [];
        const valueCells = Array.from(gridRow.querySelectorAll('td'));
        valueCells.forEach((cell, index) => {
          const fallbackKey = 'col_' + String(index + 1);
          const headerText = headerCells[index]?.textContent || fallbackKey;
          const key = toFieldKey(headerText) || fallbackKey;
          rowData[key] = (cell.textContent || '').trim();
        });
        return rowData;
      };

      const deriveTrigger = (event, source) => {
        if (source?.closest('.grid-row')) {
          return event.type === 'dblclick' ? 'row_dblclick' : 'row_click';
        }
        if (source?.dataset?.trigger) return source.dataset.trigger;
        const triggerEl = source?.closest('[data-trigger]');
        if (triggerEl) return triggerEl.dataset.trigger;
        if (source?.matches('select')) return 'select_change';
        if (source?.matches('input, textarea')) return 'input';
        if (event.type === 'submit') return 'submit';
        return 'click';
      };

      const refreshComponents = (componentIds) => {
        if (!Array.isArray(componentIds)) return;
        for (const id of componentIds) {
          const el = document.getElementById(id);
          if (el && window.htmx) {
            window.htmx.trigger(el, 'load');
          }
        }
      };

      const handleActionEvent = async (event) => {
        const source = event.target instanceof Element
          ? event.target
          : event.target?.parentElement || null;
        const wrapper = source?.closest('[data-actions]');
        if (!wrapper) return;

        const trigger = deriveTrigger(event, source);
        const actionConfig = parseActions(wrapper.dataset.actions);

        const actionOrActions = actionConfig[trigger];
        if (!actionOrActions) return;

        const actionsToRun = Array.isArray(actionOrActions) ? actionOrActions : [actionOrActions];
        const gridRow = source?.closest('.grid-row');
        const rowData = deriveGridRowData(gridRow);

        const elementContext = {};
        if (source?.matches('select, input, textarea')) {
          elementContext.selected_value = source.value;
          elementContext.value = source.value;
        }

        if (event.type === 'submit') {
          event.preventDefault();
        }

        for (const action of actionsToRun) {
          const resolvedAction = resolvePlaceholders(action, { ...rowData, ...elementContext });
          const handled = await window.__actionHandlers(resolvedAction, {
            rowData, elementContext, wrapper, event, getActionValue, applySwap, refreshComponents
          });
          if (handled === 'stop') return;
        }
      };

      for (const eventName of ['change', 'click', 'dblclick', 'input', 'submit']) {
        document.addEventListener(eventName, handleActionEvent);
      }
`;
