// Save gate: keep a form's Save button disabled until the form is valid. Opt-in, so one form can adopt it without touching any other:
//
//   <form class="form-container" data-require-valid> ... </form>
//
// A form is valid when the browser says so (form.checkValidity(): every `required` control filled, number/date types sane) AND every element
// marked data-required holds a <select> with a value. The second rule exists because a dropdown cannot carry `required` today (the
// {{{x_dd:f_col}}} widget is rendered by api_select_form, which only knows a template and a field name, and the searchable select wraps the
// native one).
//
// The Save button lives outside the form, in the inline form panel header, tied to it by its form attribute (id inline_form_element, set when
// the form is injected). Forms are injected with innerHTML, so nothing here can rely on a <script> inside the template: one cheap pass per
// animation frame after any DOM change, plus a pass on every input/change inside an opted-in form.
export const saveGateCode = `
      (() => {
        const saveButton = (form) => form.id
          ? document.querySelector('button[type="submit"][form="' + form.id + '"]')
          : null;

        const isValid = (form) => {
          if (!form.checkValidity()) return false;
          const hosts = form.querySelectorAll('[data-required]');
          for (let i = 0; i < hosts.length; i++) {
            const sel = hosts[i].querySelector('select');
            if (sel && !sel.value) return false;
          }
          return true;
        };

        const refresh = (form) => {
          const btn = saveButton(form);
          if (!btn) return;
          const ok = isValid(form);
          btn.disabled = !ok;
          btn.style.opacity = ok ? '' : '0.5';
          btn.style.cursor = ok ? '' : 'not-allowed';
          btn.title = ok ? '' : 'Fill in the required fields (*) to save';
        };

        const refreshAll = () => document.querySelectorAll('form[data-require-valid]').forEach(refresh);

        ['input', 'change'].forEach((type) => document.addEventListener(type, (e) => {
          const form = e.target && e.target.closest ? e.target.closest('form[data-require-valid]') : null;
          if (form) refresh(form);
        }));

        let scheduled = false;
        new MutationObserver(() => {
          if (scheduled) return;
          scheduled = true;
          requestAnimationFrame(() => { scheduled = false; refreshAll(); });
        }).observe(document.documentElement, { childList: true, subtree: true });
      })();
`;
