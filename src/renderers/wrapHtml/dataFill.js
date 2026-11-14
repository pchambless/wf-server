// Dropdown-driven pre-fill. An <option> can name values for other fields in the same <form>; choosing it
// fills those fields, but only the ones that are still empty, so nothing the user typed is overwritten:
//
//   <option value="api_key" data-fill='{"f_title":"API key request","f_message":"Please send me an API key."}'>
//
//   data-fill   JSON object: field NAME -> text. Unknown names are ignored.
//
// Why page-level code and not an onchange="" in the template: the app's CSP has script-src-attr 'none', so inline
// event attributes never run (task 718 found this on the Feedback form). One delegated listener serves every form.
// Fires for Tom Select dropdowns too: they write to the native <select> and dispatch a bubbling 'change'.
export const dataFillCode = `
      document.addEventListener('change', (e) => {
        const sel = e.target;
        if (!(sel instanceof HTMLSelectElement) || !sel.form) return;
        const raw = sel.selectedOptions[0]?.getAttribute('data-fill');
        if (!raw) return;
        let fill;
        try { fill = JSON.parse(raw); } catch { return; }
        if (!fill || typeof fill !== 'object') return;
        Object.entries(fill).forEach(([name, text]) => {
          const field = sel.form.elements.namedItem(name);
          if ((field instanceof HTMLInputElement || field instanceof HTMLTextAreaElement) && field.value.trim() === '') {
            field.value = String(text);
            field.dispatchEvent(new Event('input', { bubbles: true }));
          }
        });
      });
`;
