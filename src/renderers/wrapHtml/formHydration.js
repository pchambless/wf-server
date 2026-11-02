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

      // The mode word (INSERT / UPDATE) stays plain; what follows it is wrapped so the name stands out. Colour: .form-title-name in the
      // grid-form-layout css.
      const setFormTitle = (titleEl, mode, name) => {
        if (!titleEl) return;
        titleEl.textContent = mode + ' ';
        const nameEl = document.createElement('span');
        nameEl.className = 'form-title-name';
        nameEl.textContent = name;
        titleEl.appendChild(nameEl);
      };
`;
