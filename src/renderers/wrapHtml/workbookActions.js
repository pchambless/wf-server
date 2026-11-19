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
        const recall = row0.recall || null;
        const trace = Array.isArray(row0.trace) ? row0.trace : [];
        trace.forEach((t) => { if (!Array.isArray(t.shipments)) t.shipments = []; });
        const unshipped = trace.filter((t) => t.shipments.length === 0).length;
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
        // Paul 2026-11-16: the maker may have no spreadsheet app; name the free ways to open it.
        const opens = r.addRow(['Open this file with Excel, Google Sheets or LibreOffice (both free), or Numbers on a Mac.']);
        r.mergeCells(opens.number, 1, opens.number, 2);
        opens.getCell(1).alignment = { wrapText: true, vertical: 'top' };
        opens.getCell(1).font = { italic: true, color: { argb: 'FF4B5563' } };
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
        if (recall) pair('Kind', recall.kind === 'real' ? 'Real recall' : 'Practice drill (mock recall)');
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
        pair('Batches with shipments recorded', trace.length - unshipped);
        pair('Batches with no shipments recorded', unshipped);
        r.addRow([]);
        // Task 890: Distribution is filled from the shipments entered on the Recall helper page.
        const note = r.addRow(['Expected quantity used (Forward Trace tab) = recipe quantity x batch ratio, from the recipe, not a measured amount. The Distribution tab lists the shipments recorded in WhatsFresh for each product batch; a batch with none recorded has one blank row to complete from your sales records.']);
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

        // Tab 3: Distribution IS the distribution template (Paul 2026-11-17, after Joel's WF v1 sales template).
        // Its columns are the spec: one row per sale/shipment, keyed by the product batch number, and the same shape a
        // future Sale batch + lineage import would read. WhatsFresh pre-fills a checklist row per product batch (A-C,
        // plus the batch's measure as a starting Unit); the maker fills D-I from their sales records or pastes an
        // accounting export that carries the batch number. No FSMA lot code here: the maker cannot produce it, and it
        // is on Forward Trace for the auditor.
        const d = wb.addWorksheet('Distribution');
        const how = d.addRow(['Distribution template: one row per sale or shipment, with the product batch number on every row. If your accounting system can export sales with the product batch number, paste those rows here in these columns; otherwise copy a batch row once for each customer (or invoice) and fill in each copy.']);
        d.mergeCells(1, 1, 1, 9);
        how.getCell(1).alignment = { wrapText: true, vertical: 'top' };
        how.getCell(1).font = { italic: true, color: { argb: 'FF4B5563' } };
        how.height = 45;
        d.addRow(['Product Batch', 'Product', 'Batch Date', 'Customer', 'Customer Location', 'Invoice / Ref #', 'Sale Date', 'Qty', 'Unit']);
        // Task 890: one row per shipment recorded on the Recall helper page; a batch with none keeps one blank
        // checklist row (warn, never block: a real recall may need a partial file within 24 hours).
        trace.forEach((t) => {
          if (t.shipments.length === 0) {
            const x = d.addRow([safeText(t.batch), safeText(t.product), isoDate(t.batch_date), null, null, null, null, null, safeText(t.batch_measure)]);
            x.getCell(3).numFmt = DATE;
            return;
          }
          t.shipments.forEach((s) => {
            const x = d.addRow([safeText(t.batch), safeText(t.product), isoDate(t.batch_date), safeText(s.customer), safeText(s.city_state),
              safeText(s.reference), isoDate(s.ship_date), num(s.qty), safeText(s.unit)]);
            x.getCell(3).numFmt = DATE;
            x.getCell(7).numFmt = DATE;
          });
        });
        const distRows = trace.reduce((n, t) => n + Math.max(1, t.shipments.length), 0);
        // Sale Date accepts dates only (Paul 2026-11-16 asked for a calendar): Google Sheets turns this into a date
        // picker on double-click; Excel and LibreOffice have no cell calendar, so they show the hint and reject
        // non-dates. Qty takes numbers only. Applied well below the data so copied or pasted rows keep it.
        const lastRow = Math.max(500, distRows * 20 + 2);
        d.dataValidations.add('G3:G' + lastRow, {
          type: 'date', operator: 'greaterThan', allowBlank: true, formulae: [new Date(Date.UTC(2000, 0, 1))],
          showInputMessage: true, promptTitle: 'Sale Date', prompt: 'Enter a date, e.g. 2026-11-16',
          showErrorMessage: true, errorStyle: 'stop', errorTitle: 'Sale Date', error: 'Please enter a date, e.g. 2026-11-16'
        });
        d.dataValidations.add('H3:H' + lastRow, {
          type: 'decimal', operator: 'greaterThanOrEqual', allowBlank: true, formulae: [0],
          showErrorMessage: true, errorStyle: 'stop', errorTitle: 'Qty', error: 'Please enter a number, e.g. 12'
        });
        for (let n = 3; n <= lastRow; n++) d.getCell('G' + n).numFmt = DATE;
        styleTable(d, 2, [16, 32, 12, 28, 24, 16, 12, 9, 10]);
        if (trace.length) d.autoFilter = { from: 'A2', to: 'I2' };
        [4, 5, 6, 7, 8, 9].forEach((c) => { d.getRow(2).getCell(c).fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FFFEF3C7' } }; });

        // "Recall Kosher Salt (Main Street Grocer) 2026-10-05.xlsx" (Paul 2026-11-16): names the lot the way a person
        // looks for it. A colon is not allowed in Windows file names, so the supplier goes in parentheses.
        // Task 890 (Paul 2026-11-19): every file of a recall is "<ingredient> <batch_number> Recall" (.xlsx here, .pdf
        // when the Recall report is printed), with no run date, so saving again in the same folder replaces it.
        const filename = [fileSafe(src.ingredient), fileSafe(src.batch_number), 'Recall'].filter(Boolean).join(' ') + '.xlsx';
        // What the file showed, kept on the lot's recalls row when the download is recorded (task 890).
        const snapshot = {
          file_name: filename, run_at: payload.run_at, run_by: payload.run_by, kind: recall ? recall.kind : null,
          source: src, batches: trace.length, batches_unshipped: unshipped,
          trace: trace.map((t) => ({ product: t.product, batch: t.batch, batch_qty: t.batch_qty, batch_measure: t.batch_measure,
            batch_date: t.batch_date, location: t.location, shipments: t.shipments }))
        };
        return { wb, filename, recall, snapshot };
      };

      // Task 890 (Paul): let the maker choose the folder. Chrome and Edge offer a Save dialog (and remember the
      // last folder per id); other browsers, or a click too old for the browser to allow the dialog, fall back to
      // the normal download. Returns 'picker', 'download', or null when the maker cancelled the dialog.
      const saveFile = async (blob, filename) => {
        if (typeof window.showSaveFilePicker === 'function') {
          try {
            const handle = await window.showSaveFilePicker({
              id: 'recall-workbook', startIn: 'documents', suggestedName: filename,
              types: [{ description: 'Excel workbook', accept: { 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': ['.xlsx'] } }]
            });
            const writable = await handle.createWritable();
            await writable.write(blob);
            await writable.close();
            return 'picker';
          } catch (err) {
            if (err && err.name === 'AbortError') return null;
          }
        }
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = filename;
        document.body.appendChild(a);
        a.click();
        a.remove();
        setTimeout(() => URL.revokeObjectURL(url), 10000);
        return 'download';
      };

      // A download is a run of the recall (task 890): update the lot's recalls row through the generic dml path.
      const recordRun = async (opts, recall, snapshot, runBy) => {
        const response = await fetch('/api/dml', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            mode: 'UPDATE', page_id: opts.page_id, map_id: recall.id,
            f_id: String(recall.id), f_run_count: String(recall.next_run_count), f_last_run_at: recall.run_at_db,
            f_last_run_by: safeText(runBy).slice(0, 100) || 'unknown', f_snapshot: JSON.stringify(snapshot)
          })
        });
        const result = await response.json().catch(() => ({}));
        if (!response.ok || !result.success) throw new Error('record_failed');
        if (Array.isArray(opts.refresh) && opts.refresh.length) refreshComponents(opts.refresh);
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
            const built = builder(ExcelJS, payload);
            if (action.record_run && !built.recall) throw new Error('no_recall');
            const buffer = await built.wb.xlsx.writeBuffer();
            const blob = new Blob([buffer], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' });
            const savedVia = await saveFile(blob, built.filename);
            if (savedVia && action.record_run) {
              built.snapshot.saved_via = savedVia;
              await recordRun(action.record_run, built.recall, built.snapshot, payload.run_by);
            }
          } catch (err) {
            alert(err.message === 'no_source'
              ? 'Select an ingredient batch first.'
              : err.message === 'no_recall'
                ? 'Start a practice drill or a real recall first.'
                : err.message === 'record_failed'
                  ? 'The workbook was saved, but the recall run could not be recorded. Please try again.'
                  : 'Could not build the workbook. Please try again.');
          } finally {
            if (button) { button.disabled = false; button.textContent = label; }
          }
        }
      };
`;
