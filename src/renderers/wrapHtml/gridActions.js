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
        const wrapper = input.closest('[data-template-name]');
        if (!wrapper) return;

        const searchTerm = input.value.trim().toLowerCase();
        const rows = getGridRows(wrapper);

        for (const row of rows) {
          const rowText = row.textContent?.toLowerCase() || '';
          row.style.display = searchTerm === '' || rowText.includes(searchTerm) ? '' : 'none';
        }
      };

      document.addEventListener('input', function(event) {
        const target = event.target instanceof HTMLInputElement ? event.target : null;
        if (!target?.matches('.grid-search .search-input, .grid-search input[type="search"], .grid-search input[type="text"]')) {
          return;
        }

        filterGridRows(target);
      });
`;
