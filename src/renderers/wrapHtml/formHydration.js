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
        // Task 891: the panel's Delete acts on the loaded record only, so it is hidden while adding a new one.
        // Every way into the inline form (row click, Add New, stay-open save) sets the title here.
        if (titleEl.id === 'inline_form_title') {
          const delBtn = document.getElementById('inline_form_delete');
          if (delBtn) delBtn.hidden = String(mode || '').toUpperCase() === 'INSERT';
        }
      };
`;
