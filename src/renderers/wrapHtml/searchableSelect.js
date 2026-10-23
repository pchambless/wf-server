// Type-to-filter dropdowns (task 615). Progressive enhancement: every <select> with more than
// MIN_OPTIONS options is upgraded with Tom Select. The native <select> stays the source of truth
// (Tom Select writes to it and fires a bubbling 'change'), so actions, cascades and the
// dd_preserve_id pattern keep working. If the library did not load, nothing here runs.
//
// Opt out per select:   data-no-search
// Alphabetical order:   data-sort="label"   (default keeps the server's order)
export const searchableSelectCode = `
      (() => {
        const MIN_OPTIONS = 5;
        if (!window.TomSelect) return;

        const signature = (sel) =>
          Array.from(sel.options).map((o) => o.value + '|' + o.text).sort().join('\\n');

        const countReal = (sel) =>
          Array.from(sel.options).filter((o) => o.value !== '').length;

        const enhance = (sel) => {
          if (!sel.isConnected || sel.tomselect || sel.multiple || sel.hasAttribute('data-no-search')) return;
          if (countReal(sel) <= MIN_OPTIONS) return;
          // A form field can ask for a blank start with data-blank-default="-- Select X --" on its wrapper.
          // Server-rendered form dropdowns carry no blank option, so the browser silently preselects the
          // first one (Celery, Amazon...); for a field where that is dangerous, prepend a real blank.
          const blankHost = sel.closest('[data-blank-default]');
          if (blankHost && !Array.from(sel.options).some((o) => o.value === '') &&
              !Array.from(sel.options).some((o) => o.defaultSelected)) {
            const opt = new Option(blankHost.getAttribute('data-blank-default') || '-- Select --', '', true, true);
            sel.insertBefore(opt, sel.firstChild);
            sel.value = '';
          }
          const blank = Array.from(sel.options).find((o) => o.value === '');
          // measure the native select first: the enhanced control copies its look so it
          // fits wherever the original did (filter bars, forms, modals)
          // (getComputedStyle is live: copy the values now, Tom Select restyles the original)
          const live = getComputedStyle(sel);
          const cs = {};
          ['fontSize', 'fontFamily', 'lineHeight', 'padding', 'border', 'borderRadius', 'backgroundColor', 'color',
            'flexGrow', 'flexShrink', 'flexBasis', 'alignSelf']
            .forEach((k) => { cs[k] = live[k]; });
          const rect = sel.getBoundingClientRect();
          const ts = new TomSelect(sel, {
            allowEmptyOption: true,
            create: false,
            maxOptions: null,
            openOnFocus: true,
            dropdownParent: 'body',   // filter bars and modals clip their children; the list must not be clipped
            closeAfterSelect: true,
            placeholder: blank ? blank.text : '',
            sortField: sel.dataset.sort === 'label' ? [{ field: 'text', direction: 'asc' }] : [{ field: '$order' }],
            // the blank '-- Select X --' option stays in the list (it clears the field) but never matches a search
            score: function (search) {
              const base = this.getScoreFunction(search);
              return (item) => (item.value === '' ? 0 : base(item));
            }
          });
          ts.__sig = signature(sel);
          if (sel.disabled) ts.disable();
          // look: computed style is readable even while the select is hidden
          const c = ts.control.style;
          c.fontSize = cs.fontSize;
          c.fontFamily = cs.fontFamily;
          c.lineHeight = cs.lineHeight;
          c.minHeight = '0';
          c.padding = cs.padding;
          c.border = cs.border;
          c.borderRadius = cs.borderRadius;
          c.backgroundColor = cs.backgroundColor;
          c.color = cs.color;
          ts.dropdown.style.fontSize = cs.fontSize;
          ts.dropdown.style.fontFamily = cs.fontFamily;
          // size: only measurable when the select was visible; otherwise the stylesheet default applies
          // layout: behave like the original inside its parent. Selects in a flex row (the form's
          // 'dropdown-with-add' puts the + button beside them) grow with flex:1, so the new control
          // gets the same flex and no pixel minimum; otherwise keep the original width as a minimum.
          ts.wrapper.style.flex = cs.flexGrow + ' ' + cs.flexShrink + ' ' + cs.flexBasis;
          ts.wrapper.style.alignSelf = cs.alignSelf;
          ts.wrapper.style.minHeight = '0';   // the control sets the height; the library default is taller than our selects
          if (parseFloat(cs.flexGrow) > 0) ts.wrapper.style.minWidth = '0';
          else if (rect.width > 0) ts.wrapper.style.minWidth = Math.ceil(rect.width) + 'px';
        };

        const scan = (root) => {
          if (!(root instanceof Element)) return;
          if (root.tagName === 'SELECT') enhance(root);
          root.querySelectorAll('select').forEach(enhance);
        };

        const release = (root) => {
          if (!(root instanceof Element)) return;
          const list = root.tagName === 'SELECT' ? [root] : Array.from(root.querySelectorAll('select'));
          list.forEach((sel) => { if (sel.tomselect) sel.tomselect.destroy(); });
        };

        // Circuit breaker: a feedback loop here must never freeze a page. If the observer fires more than
        // MAX_BURST times inside one second it disconnects itself; dropdowns stay as they are, now plain.
        const MAX_BURST = 300;
        let burstStart = Date.now();
        let burstCount = 0;
        const observer = new MutationObserver((records) => {
          const now = Date.now();
          if (now - burstStart > 1000) { burstStart = now; burstCount = 0; }
          if (++burstCount > MAX_BURST) {
            observer.disconnect();
            console.error('searchableSelect: mutation loop detected, enhancer disabled for this page');
            return;
          }
          for (const r of records) {
            if (r.target instanceof Element && !r.target.isConnected) continue;   // destroy() rewrites detached selects
            if (r.type === 'attributes') {
              const ts = r.target.tomselect;
              // Only act on a real change: Tom Select writes 'disabled' back to the select itself,
              // so reacting unconditionally re-fires this observer forever (froze the page when a form
              // toggled a hidden dropdown with data-visible-mode).
              if (ts) {
                const want = r.target.disabled;
                if (want !== !!ts.isDisabled) { if (want) ts.disable(); else ts.enable(); }
              }
              continue;
            }
            r.removedNodes.forEach(release);
            r.addedNodes.forEach(scan);
            // options changed in place (cascading dropdowns refresh this way)
            if (r.target instanceof Element && r.target.tagName === 'SELECT') {
              const sel = r.target;
              if (!sel.tomselect) { enhance(sel); continue; }
              const sig = signature(sel);
              if (sig !== sel.tomselect.__sig) {   // ignore Tom Select reordering its own options
                sel.tomselect.__sig = sig;
                sel.tomselect.clearOptions();
                sel.tomselect.sync();
              }
            }
          }
        });
        observer.observe(document.documentElement, {
          childList: true, subtree: true, attributes: true, attributeFilter: ['disabled']
        });

        document.addEventListener('DOMContentLoaded', () => scan(document.body));
        if (document.readyState !== 'loading') scan(document.body);
      })();
`;
