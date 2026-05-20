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

      const handleActionEvent = async (event) => {
        const source = event.target instanceof Element ? event.target : null;
        const wrapper = source?.closest('[data-actions]');
        if (!wrapper) return;

        const actions = parseActions(wrapper.dataset.actions);
        const action = actions.find(candidate => candidate.trigger === event.type);
        if (!action) return;

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
