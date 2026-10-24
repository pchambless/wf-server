// Live calculated fields. A read-only <input> declares what it is the product of, and it refreshes as the user types:
//
//   <input id="f_total" readonly data-calc-product="f_quantity,f_unit_price" data-calc-prefix="$" />
//
//   data-calc-product   comma-separated NAMES of inputs in the same <form>; the field shows their product (blank or non-numeric counts as 0)
//   data-calc-prefix    text shown before the number (default none)
//   data-calc-decimals  decimal places (default 2, matching numeric(10,2) totals such as whatsfresh.vw_batches_fda.total)
//
// Why a page-level enhancer and not a <script> in the form template: forms are injected with innerHTML, and a <script> added
// that way never runs (the old inline calculation in ingredient_batch_form never did). A MutationObserver recalculates a field when
// its form is injected, so an edited row shows the value from its current inputs.
export const calcFieldsCode = `
      (() => {
        const num = (v) => { const n = parseFloat(v); return Number.isFinite(n) ? n : 0; };

        const compute = (out) => {
          const names = (out.getAttribute('data-calc-product') || '').split(',').map((s) => s.trim()).filter(Boolean);
          if (!names.length) return;
          const scope = out.closest('form') || document;
          let product = 1;
          names.forEach((name) => {
            const el = scope.querySelector('[name="' + name + '"]');
            product *= num(el && el.value);
          });
          const decimals = parseInt(out.getAttribute('data-calc-decimals') || '2', 10);
          out.value = (out.getAttribute('data-calc-prefix') || '') + product.toFixed(decimals);
        };

        const computeAll = (root) => {
          if (!root || !root.querySelectorAll) return;
          if (root.matches && root.matches('[data-calc-product]')) compute(root);
          root.querySelectorAll('[data-calc-product]').forEach(compute);
        };

        ['input', 'change'].forEach((type) => document.addEventListener(type, (e) => {
          const form = e.target && e.target.closest ? e.target.closest('form') : null;
          if (form) computeAll(form);
        }));

        // one cheap pass per frame after any DOM insertion (a big grid inserts hundreds of nodes during load)
        let scheduled = false;
        new MutationObserver(() => {
          if (scheduled) return;
          scheduled = true;
          requestAnimationFrame(() => { scheduled = false; computeAll(document); });
        }).observe(document.documentElement, { childList: true, subtree: true });

        computeAll(document);
      })();
`;
