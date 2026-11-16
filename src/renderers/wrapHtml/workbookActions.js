// Recall workbook (.xlsx) built in the browser (task 879). Rows come from POST /api/report-data (template
// rpt_recall_workbook); ExcelJS is vendored under public/vendor and loaded on the first click only.
// No backticks or dollar-brace inside: this file is injected through a template literal.
export const workbookActionsCode = `
      const EXCELJS_SRC = '/vendor/exceljs/4.4.0/exceljs.min.js';
      let excelJsLoading = null;
      const loadExcelJs = () => {
        if (window.ExcelJS) return Promise.resolve(window.ExcelJS);
        if (!excelJsLoading) {
          excelJsLoading = new Promise((resolve, reject) => {
            const s = document.createElement('script');
            s.src = EXCELJS_SRC;
            s.onload = () => window.ExcelJS ? resolve(window.ExcelJS) : reject(new Error('ExcelJS missing'));
            s.onerror = () => { excelJsLoading = null; reject(new Error('ExcelJS failed to load')); };
            document.head.appendChild(s);
          });
        }
        return excelJsLoading;
      };

      // Every value goes in as a plain string or number, never { formula }: ExcelJS writes strings as typed text
      // cells, which Excel never evaluates, so text starting with = + - @ cannot run (no prefix needed, which
      // would also change lot codes that really start with '-').
      const safeText = (v) => (v === null || v === undefined) ? '' : String(v);
      const num = (v) => (v === null || v === undefined || v === '' || isNaN(Number(v))) ? null : Number(v);
      // 'YYYY-MM-DD' -> a real Excel date (UTC midnight, so no time-zone day shift).
      const isoDate = (v) => {
        const m = /^(\\d{4})-(\\d{2})-(\\d{2})/.exec(String(v || ''));
        return m ? new Date(Date.UTC(+m[1], +m[2] - 1, +m[3])) : null;
      };
      // Readable file-name part: keeps spaces, drops what Windows/macOS refuse in a name (\\ / : * ? " < > | and control chars).
      const fileSafe = (s) => String(s || '').replace(/[\\\\/:*?"<>|\\u0000-\\u001f]+/g, ' ').replace(/\\s+/g, ' ').trim().replace(/[. ]+$/, '').slice(0, 60);

      const styleTable = (ws, headerRow, widths) => {
        const hdr = ws.getRow(headerRow);
        hdr.font = { bold: true };
        hdr.eachCell((c) => {
          c.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FFE5E7EB' } };
          c.border = { bottom: { style: 'thin' } };
        });
        ws.views = [{ state: 'frozen', ySplit: headerRow }];
        widths.forEach((w, i) => { ws.getColumn(i + 1).width = w; });
        ws.pageSetup = { orientation: 'landscape', fitToPage: true, fitToWidth: 1, fitToHeight: 0, printTitlesRow: headerRow + ':' + headerRow };
      };

      const buildRecallWorkbook = (ExcelJS, payload) => {
        const row0 = (payload.data && payload.data.rpt_recall_workbook && payload.data.rpt_recall_workbook[0]) || {};
        const src = row0.source;
        const trace = Array.isArray(row0.trace) ? row0.trace : [];
        if (!src) throw new Error('no_source');

        const wb = new ExcelJS.Workbook();
        wb.creator = 'WhatsFresh';
        wb.created = new Date(payload.run_at);
        const DATE = 'yyyy-mm-dd';

        // Tab 1: Recall (drill record, source purchase, summary)
        const r = wb.addWorksheet('Recall');
        r.getColumn(1).width = 30;
        r.getColumn(2).width = 48;
        const title = r.addRow(['Ingredient Recall / Mock Recall Record']);
        title.font = { bold: true, size: 14 };
        // Paul 2026-11-16 (review of the first sample): say how the file was made; headings in colour, labels regular.
        const about = r.addRow(['Created by the WhatsFresh app. WhatsFresh records every ingredient purchase as its own batch, with an FSMA lot code, supplier and vendor lot. Each time a product batch is made, the ingredient batches that went into it are recorded against it, so any purchase can be traced forward to every product batch that used it.']);
        r.mergeCells(about.number, 1, about.number, 2);
        about.getCell(1).alignment = { wrapText: true, vertical: 'top' };
        about.getCell(1).font = { italic: true, color: { argb: 'FF4B5563' } };
        about.height = 60;
        const HEADING = { bold: true, size: 12, color: { argb: 'FFBF0041' } };
        const section = (label) => { r.addRow([]); const x = r.addRow([label]); x.font = HEADING; };
        const pair = (label, value, fmt) => {
          const x = r.addRow([label, value === null || value === undefined ? '' : value]);
          x.getCell(2).alignment = { horizontal: 'left' };
          if (fmt) x.getCell(2).numFmt = fmt;
        };

        // Excel has no time zone and ExcelJS writes a Date as UTC: store the viewer's local wall-clock time.
        const ran = new Date(payload.run_at);
        const ranLocal = new Date(Date.UTC(ran.getFullYear(), ran.getMonth(), ran.getDate(), ran.getHours(), ran.getMinutes(), ran.getSeconds()));
        section('Drill record');
        pair('Run date and time', ranLocal, 'yyyy-mm-dd hh:mm');
        pair('Run by', safeText(payload.run_by));
        pair('Lot recalled (FSMA Lot Code)', safeText(src.fsma_lot_code));

        section('Source purchase');
        pair('Ingredient', safeText([src.ingredient_type, src.ingredient].filter(Boolean).join('.')));
        pair('FSMA Lot Code', safeText(src.fsma_lot_code));
        pair('Batch Number', safeText(src.batch_number));
        pair('Purchase Date', isoDate(src.purchase_date), DATE);
        pair('Supplier (purchased from)', safeText(src.supplier));
        pair('Vendor Lot', safeText(src.vendor_lot));
        pair('Brand', safeText(src.brand));
        pair('Quantity', num(src.batch_qty));
        pair('Measure', safeText(src.measure));
        if (src.best_by_date) pair('Best By', isoDate(src.best_by_date), DATE);

        section('Summary');
        pair('Affected product batches', trace.length);
        r.addRow([]);
        const note = r.addRow(['Expected quantity used (Forward Trace tab) = recipe quantity x batch ratio, from the recipe, not a measured amount. Who received each product batch is completed on the Distribution tab from your sales records.']);
        r.mergeCells(note.number, 1, note.number, 2);
        note.getCell(1).alignment = { wrapText: true, vertical: 'top' };
        note.height = 45;
        r.pageSetup = { orientation: 'portrait', fitToPage: true, fitToWidth: 1, fitToHeight: 0 };

        // Tab 2: Forward Trace (the Ingredient Batch Tracing report's rows, same sort)
        const f = wb.addWorksheet('Forward Trace');
        f.addRow(['Product', 'Batch', 'FSMA Lot Code', 'Batch Qty', 'Batch Measure', 'Expected Qty Used', 'Measure', 'Date', 'Location']);
        trace.forEach((t) => {
          const x = f.addRow([safeText(t.product), safeText(t.batch), safeText(t.fsma_lot_code), num(t.batch_qty), safeText(t.batch_measure),
            num(t.expected_qty), safeText(t.expected_measure), isoDate(t.batch_date), safeText(t.location)]);
          x.getCell(8).numFmt = DATE;
          x.getCell(6).numFmt = '0.####';
        });
        styleTable(f, 1, [32, 16, 26, 10, 14, 17, 12, 12, 28]);
        if (trace.length) f.autoFilter = { from: 'A1', to: 'I1' };

        // Tab 3: Distribution (pre-filled per product batch; the maker completes who received it)
        // Row 1 says how to fill it in (Paul 2026-11-16: one row per shipment); the table starts at row 2.
        const d = wb.addWorksheet('Distribution');
        const how = d.addRow(['Fill in one row per shipment, from your sales records. If a product batch went to more than one customer, copy its row once for each customer (or invoice) and fill in each copy.']);
        d.mergeCells(1, 1, 1, 8);
        how.getCell(1).alignment = { wrapText: true, vertical: 'top' };
        how.getCell(1).font = { italic: true, color: { argb: 'FF4B5563' } };
        how.height = 32;
        d.addRow(['Product', 'Product Batch', 'FSMA Lot Code', 'Batch Date', 'Customer', 'Invoice #', 'Qty Shipped', 'Date Shipped']);
        trace.forEach((t) => {
          const x = d.addRow([safeText(t.product), safeText(t.batch), safeText(t.fsma_lot_code), isoDate(t.batch_date), null, null, null, null]);
          x.getCell(4).numFmt = DATE;
          x.getCell(8).numFmt = DATE;
        });
        // Date Shipped accepts dates only (Paul 2026-11-16 asked for a calendar): Google Sheets turns this into a
        // date picker on double-click; Excel and LibreOffice have no cell calendar, so they show the hint and reject
        // non-dates. Applied well below the data so rows the maker copies for more customers keep it.
        const lastRow = Math.max(500, trace.length * 20 + 2);
        d.dataValidations.add('H3:H' + lastRow, {
          type: 'date', operator: 'greaterThan', allowBlank: true, formulae: [new Date(Date.UTC(2000, 0, 1))],
          showInputMessage: true, promptTitle: 'Date Shipped', prompt: 'Enter a date, e.g. 2026-11-16',
          showErrorMessage: true, errorStyle: 'stop', errorTitle: 'Date Shipped', error: 'Please enter a date, e.g. 2026-11-16'
        });
        for (let n = 3; n <= lastRow; n++) d.getCell('H' + n).numFmt = DATE;
        styleTable(d, 2, [32, 16, 26, 12, 28, 14, 12, 14]);
        if (trace.length) d.autoFilter = { from: 'A2', to: 'H2' };
        [5, 6, 7, 8].forEach((c) => { d.getRow(2).getCell(c).fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FFFEF3C7' } }; });

        // "Recall Kosher Salt (Main Street Grocer) 2026-10-05.xlsx" (Paul 2026-11-16): names the lot the way a person
        // looks for it. A colon is not allowed in Windows file names, so the supplier goes in parentheses.
        const ingredient = fileSafe(src.ingredient) || fileSafe(src.batch_number) || 'Lot';
        const supplier = fileSafe(src.supplier);
        const when = fileSafe(src.purchase_date) || ranLocal.toISOString().slice(0, 10);
        return { wb, filename: 'Recall ' + ingredient + (supplier ? ' (' + supplier + ')' : '') + ' ' + when + '.xlsx' };
      };

      const WORKBOOKS = { recall: buildRecallWorkbook };

      window.workbookExport = {
        run: async (action, contextData, button) => {
          const builder = WORKBOOKS[action.workbook];
          const templates = action.templates || [];
          if (!builder || templates.length === 0) return;
          const label = button ? button.textContent : '';
          if (button) { button.disabled = true; button.textContent = 'Building\\u2026'; }
          try {
            const [ExcelJS, response] = await Promise.all([
              loadExcelJs(),
              fetch('/api/report-data', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ templates, ...contextData })
              })
            ]);
            const payload = await response.json().catch(() => ({}));
            if (!response.ok || !payload.success) throw new Error(payload.message || 'request_failed');
            const { wb, filename } = builder(ExcelJS, payload);
            const buffer = await wb.xlsx.writeBuffer();
            const blob = new Blob([buffer], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' });
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = filename;
            document.body.appendChild(a);
            a.click();
            a.remove();
            setTimeout(() => URL.revokeObjectURL(url), 10000);
          } catch (err) {
            alert(err.message === 'no_source'
              ? 'Select an ingredient batch first.'
              : 'Could not build the workbook. Please try again.');
          } finally {
            if (button) { button.disabled = false; button.textContent = label; }
          }
        }
      };
`;
