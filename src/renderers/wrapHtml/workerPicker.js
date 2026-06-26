export const workerPickerCode = `
      const initWorkerPicker = () => {
        const workersField = document.getElementById('f_workers');
        const display = document.getElementById('workers_display');
        const container = document.getElementById('worker_checkboxes');
        if (!workersField || !container) return;

        // Pre-check boxes based on existing workers value
        const existing = (workersField.value || '')
          .split(',')
          .map(s => s.trim())
          .filter(Boolean);

        const checkboxes = container.querySelectorAll('.worker-cb');
        checkboxes.forEach(cb => {
          if (existing.includes(cb.value)) {
            cb.checked = true;
          }
        });

        // On any checkbox change, rebuild the workers string
        container.addEventListener('change', (e) => {
          if (!e.target.classList.contains('worker-cb')) return;

          const selected = Array.from(container.querySelectorAll('.worker-cb:checked'))
            .map(cb => cb.value);

          const val = selected.join(', ');
          workersField.value = val;
          if (display) display.textContent = val || '(none selected)';
        });
      };
`;
