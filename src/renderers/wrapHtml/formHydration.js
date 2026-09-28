export const formHydrationCode = `
      const applyModeVisibility = (container, mode) => {
        const normalizedMode = String(mode || 'INSERT').toLowerCase();
        container.querySelectorAll('[data-visible-mode]').forEach((el) => {
          const modes = el.dataset.visibleMode.split(',').map((m) => m.trim().toLowerCase());
          const show = modes.includes(normalizedMode);
          el.style.display = show ? '' : 'none';
          el.querySelectorAll('input, select, textarea').forEach((field) => {
            field.disabled = !show;
          });
        });
      };
`;
