// Select-first hint (task 474). On any page with a filter dropdown bar
// (.dropdown-container), a blank dropdown means the rows below cannot be
// meaningful yet. Hide everything under the bar and say which dropdowns still
// need a value. When every dropdown has a value (e.g. prefilled from
// context_store) the content shows normally and no hint appears.
//
// Client-side on purpose: it covers every page that uses the shared bar with
// no per-grid SQL. The grids still fetch in the background; they are only
// hidden, not prevented from loading.
export const filterHintCode = `
      const filterHint = {
        // The slot renders <div class="dropdown-label"> then a component wrapper
        // div (htmx target) as siblings in the bar, with the <select> nested inside
        // the wrapper - so climb to the bar's direct child before looking back.
        label: (select) => {
          const bar = select.closest('.dropdown-container');
          let wrap = select;
          while (wrap && wrap.parentElement !== bar) wrap = wrap.parentElement;
          const prev = wrap ? wrap.previousElementSibling : null;
          const text = prev && prev.classList.contains('dropdown-label') ? prev.textContent : '';
          return (text || '').trim() || 'value';
        },

        article: (word) => (/^[aeiou]/i.test(word) ? 'an' : 'a'),

        message: (labels) => {
          const parts = labels.map(l => filterHint.article(l) + ' ' + l);
          return 'Select ' + parts.join(', then ') + ' to continue.';
        },

        update: () => {
          const bar = document.querySelector('.dropdown-container');
          if (!bar) return;

          const selects = Array.from(bar.querySelectorAll('select'));
          if (selects.length === 0) return;

          const missing = selects.filter(s => !s.value).map(filterHint.label);

          // Everything under the bar (grids, forms, panels) except scripts and our own hint.
          const below = [];
          for (let el = bar.nextElementSibling; el; el = el.nextElementSibling) {
            if (el.id !== 'filter_hint' && el.tagName !== 'SCRIPT') below.push(el);
          }

          let hint = document.getElementById('filter_hint');

          if (missing.length === 0) {
            if (hint) hint.remove();
            below.forEach(el => {
              if (el.dataset.filterHidden) {
                el.style.display = el.dataset.filterHidden === '__none__' ? '' : el.dataset.filterHidden;
                delete el.dataset.filterHidden;
              }
            });
            return;
          }

          if (!hint) {
            hint = document.createElement('div');
            hint.id = 'filter_hint';
            hint.className = 'filter-hint';
            bar.insertAdjacentElement('afterend', hint);
          }
          hint.textContent = filterHint.message(missing);

          below.forEach(el => {
            if (!el.dataset.filterHidden) el.dataset.filterHidden = el.style.display || '__none__';
            el.style.display = 'none';
          });
        }
      };

      // Dropdowns hydrate asynchronously and context prefill lands after that, so
      // re-evaluate after every htmx settle as well as on user changes.
      document.addEventListener('DOMContentLoaded', filterHint.update);
      document.addEventListener('htmx:afterSettle', filterHint.update);
      document.addEventListener('change', (e) => {
        if (e.target instanceof Element && e.target.closest('.dropdown-container')) filterHint.update();
      });
`;
