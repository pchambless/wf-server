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

      const handleActionEvent = async (event) => {
        const source = event.target instanceof Element ? event.target : null;
        const wrapper = source?.closest('[data-actions]');
        if (!wrapper) return;

        const trigger = deriveTrigger(event, source);
        const actionConfig = parseActions(wrapper.dataset.actions);

        const actionOrActions = actionConfig[trigger];
        if (!actionOrActions) return;

        const actionsToRun = Array.isArray(actionOrActions) ? actionOrActions : [actionOrActions];
        const gridRow = source?.closest('.grid-row');
        const rowData = gridRow ? { id: gridRow.dataset.rowId, ...gridRow.dataset } : {};

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

          const response = await fetch('/api/actions', {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json'
            },
            body: JSON.stringify({
              component_id: wrapper.id,
              template_name: wrapper.dataset.templateName,
              value: getActionValue(event, wrapper),
              action: resolvedAction
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
        }
      };

      for (const eventName of ['change', 'click', 'dblclick', 'input', 'submit']) {
        document.addEventListener(eventName, handleActionEvent);
      }
`;
