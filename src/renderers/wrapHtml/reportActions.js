export const reportActionsCode = `
      const ensureReportModal = () => {
        let modal = document.getElementById('report_modal');
        if (modal) return modal;

        modal = document.createElement('div');
        modal.id = 'report_modal';
        modal.className = 'modal-overlay hidden';
        modal.innerHTML = \`
          <div style="background:#fff;border-radius:8px;box-shadow:0 4px 24px rgba(0,0,0,0.18);width:100%;max-width:900px;max-height:90vh;display:flex;flex-direction:column;">
            <div style="display:flex;justify-content:space-between;align-items:center;padding:16px 20px;border-bottom:1px solid #e5e7eb;flex-shrink:0;">
              <h2 id="report_modal_title" style="margin:0;font-size:18px;font-weight:700;"></h2>
              <button type="button" id="report_modal_close" style="background:none;border:none;cursor:pointer;font-size:24px;line-height:1;color:#6b7280;">&times;</button>
            </div>
            <div id="report_modal_body" style="padding:20px;overflow-y:auto;flex:1;min-height:0;"></div>
          </div>
        \`;
        document.body.appendChild(modal);

        document.getElementById('report_modal_close').addEventListener('click', () => {
          window.reportModal.close();
        });
        modal.addEventListener('click', (e) => {
          if (e.target === modal) window.reportModal.close();
        });

        // Delegate print button clicks (CSP blocks inline onclick handlers)
        modal.addEventListener('click', (e) => {
          if (e.target.closest('.print-btn')) {
            window.print();
          }
        });

        return modal;
      };

      // Save as PDF names the file after the page title. A report that carries data-file-name (task 890: the Recall
      // report, "<ingredient> <batch_number> Recall") gets that title while printing, by the Print button or Ctrl+P.
      let titleBeforePrint = null;
      window.addEventListener('beforeprint', () => {
        const modal = document.getElementById('report_modal');
        const named = modal && !modal.classList.contains('hidden') ? modal.querySelector('[data-file-name]') : null;
        const name = named ? named.getAttribute('data-file-name').replace(/[\\\\/:*?"<>|\\u0000-\\u001f]+/g, ' ').replace(/\\s+/g, ' ').trim() : '';
        if (!name) return;
        titleBeforePrint = document.title;
        document.title = name;
      });
      window.addEventListener('afterprint', () => {
        if (titleBeforePrint === null) return;
        document.title = titleBeforePrint;
        titleBeforePrint = null;
      });

      window.reportModal = {
        // Last report opened, so a pop-up form saved on top of it can reload it (task 889: Add shipment in the Recall report).
        _last: null,

        open: async (templates, contextData) => {
          window.reportModal._last = { templates, contextData };
          const modal = ensureReportModal();
          const body = document.getElementById('report_modal_body');
          const titleEl = document.getElementById('report_modal_title');
          if (titleEl) titleEl.textContent = 'Loading\u2026';
          body.innerHTML = '<div style="padding:20px;text-align:center;color:#6b7280;">Loading\u2026</div>';
          modal.classList.remove('hidden');
          document.body.style.overflow = 'hidden';

          try {
            const response = await fetch('/api/report', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ templates, ...contextData })
            });
            if (!response.ok) throw new Error('Report request failed');
            const html = await response.text();
            body.innerHTML = html;
            const firstH2 = body.querySelector('h2, h1, .subject');
            if (titleEl) titleEl.textContent = firstH2 ? firstH2.textContent : 'Report';
          } catch (err) {
            body.innerHTML = '<div style="color:#dc2626;padding:12px;">Failed to load report.</div>';
            if (titleEl) titleEl.textContent = 'Error';
          }
        },

        // Re-run the open report in place, keeping the scroll position. No-op when no report is showing.
        reload: async () => {
          const modal = document.getElementById('report_modal');
          const last = window.reportModal._last;
          if (!modal || modal.classList.contains('hidden') || !last) return;
          const body = document.getElementById('report_modal_body');
          const scrollTop = body ? body.scrollTop : 0;
          await window.reportModal.open(last.templates, last.contextData);
          if (body) body.scrollTop = scrollTop;
        },

        close: () => {
          const modal = document.getElementById('report_modal');
          if (modal) modal.classList.add('hidden');
          document.body.style.overflow = '';
        }
      };
`;
