export const gridActionsCode = `
      const getGridRows = (wrapper) => {
        if (!wrapper) return [];

        const explicitRows = Array.from(wrapper.querySelectorAll('.page-grid .grid-row, .table .grid-row'));
        if (explicitRows.length > 0) {
          return explicitRows;
        }

        return Array.from(wrapper.querySelectorAll('.page-grid tbody tr, .table tbody tr'));
      };

      const filterGridRows = (input) => {
        let wrapper = input.closest('[data-template-name]');

        // If not in a component, look for grid in the same page container
        if (!wrapper) {
          const page = input.closest('.crud-page');
          wrapper = page?.querySelector('[data-template-name]');
        }

        if (!wrapper) return;

        const searchTerm = input.value.trim().toLowerCase();
        const rows = getGridRows(wrapper);

        for (const row of rows) {
          const rowText = row.textContent?.toLowerCase() || '';
          row.style.display = searchTerm === '' || rowText.includes(searchTerm) ? '' : 'none';
        }
      };

      const handleGridRowSelection = (event) => {
        const source = event.target instanceof Element ? event.target : null;
        if (!source) return;

        const row = source.closest('.grid-row, tbody tr');
        if (!row || !row.matches('tr, .grid-row')) return;

        // Find the grid wrapper to deselect other rows
        const wrapper = row.closest('[data-template-name], .page-grid, .table');
        if (!wrapper) return;

        // Only toggle selection on direct row click, not on clicks that trigger actions
        const hasActions = row.closest('[data-actions]');
        if (hasActions && source !== row) return;

        // Deselect all other rows in this grid
        const rows = wrapper.querySelectorAll('.grid-row, tbody tr');
        rows.forEach(r => r.classList.remove('selected'));

        // Select the clicked row
        row.classList.add('selected');
      };

      document.addEventListener('input', function(event) {
        const target = event.target instanceof HTMLInputElement ? event.target : null;
        if (!target?.matches('.grid-search .search-input, .grid-search input[type="search"], .grid-search input[type="text"], .grid-toolbar .search-input')) {
          return;
        }

        filterGridRows(target);
      });

      document.addEventListener('click', handleGridRowSelection);
`;
