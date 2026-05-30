import { actionEngineCode } from './actionEngine.js';
import { gridActionsCode } from './gridActions.js';
import { selectActionsCode } from './selectActions.js';
import { formActionsCode } from './formActions.js';
import { reportActionsCode } from './reportActions.js';

export function wrapHtml(title, body) {
  const styleRegex = /<style[^>]*>[\s\S]*?<\/style>/gi;
  const styles = [];

  const fallbackUiStyles = `<style>
    .hidden { display: none !important; }
    .wf-slot-actions {
      display: inline-flex;
      align-items: stretch;
      flex-wrap: nowrap;
      gap: 0;
      margin: 8px 0;
      border: 2px solid #000000;
      border-radius: 8px;
      overflow: hidden;
      background: #fecaca;
    }
    .wf-slot-actions .wf-slot-action-btn {
      border: 0;
      border-right: 2px solid #000000;
      border-radius: 0;
      padding: 6px 12px;
      background: #fecaca;
      color: #111827;
      cursor: pointer;
      white-space: nowrap;
      font-weight: 600;
    }
    .wf-slot-actions .wf-slot-action-btn:last-child {
      border-right: 0;
    }
    .wf-slot-actions .wf-slot-action-btn:hover {
      background: #fca5a5;
      color: #111827;
    }
    .wf-slot-actions .wf-slot-action-btn:focus-visible {
      outline: 2px solid #000000;
      outline-offset: 2px;
    }
    .wf-context-btn-group {
      background: #bbf7d0;
    }
    .wf-context-btn-group .wf-context-btn {
      background: #bbf7d0;
    }
    .wf-context-btn-group .wf-context-btn:hover {
      background: #86efac;
      color: #111827;
    }
    .grid-toolbar {
      display: flex;
      align-items: center;
      gap: 12px;
      margin-bottom: 16px;
    }
    .grid-toolbar .search-input {
      width: 180px;
      padding: 8px 12px;
      border: 1px solid #d1d5db;
      border-radius: 4px;
      font-size: 14px;
    }
    .grid-toolbar .toolbar-actions {
      display: flex;
      gap: 8px;
    }
    .appbar {
      display: flex;
      align-items: center;
      gap: 10px;
      padding: 12px 14px;
      background: var(--accent-color, #16a34a);
      color: white;
      font-family: var(--font-family, "Segoe UI", Arial, sans-serif);
      justify-content: center;
    }
    .appbar .wf-icon {
      width: 24px;
      height: 24px;
      flex: 0 0 auto;
      position: absolute;
      left: 14px;
    }
    .appbar .title {
      font-size: 18px;
      font-weight: 600;
      line-height: 1.2;
      text-align: center;
      flex: 1;
    }
    .appbar .first-name {
      font-size: 14px;
      line-height: 1.2;
      margin-left: auto;
      padding: 4px 8px;
    }
    .appbar .account-name {
      font-size: 14px;
      line-height: 1.2;
      padding: 4px 8px;
      border-radius: 4px;
      background: rgba(255,255,255,0.14);
      border: 1px solid rgba(255,255,255,0.22);
    }
    .appbar button,
    .appbar .logout-btn {
      background: rgba(255,255,255,0.15);
      color: white;
      border: 1px solid rgba(255,255,255,0.3);
      padding: 6px 12px;
      border-radius: 4px;
      cursor: pointer;
      font-size: 12px;
      line-height: 1.2;
    }
    .appbar button:hover,
    .appbar .logout-btn:hover {
      background: rgba(255,255,255,0.25);
    }
    .modal-overlay {
      position: fixed;
      inset: 0;
      background: rgba(0, 0, 0, 0.45);
      z-index: 1000;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 16px;
    }
    @media print {
      body > *:not(#report_modal) { display: none !important; }
      #report_modal {
        position: static !important;
        background: none !important;
        padding: 0 !important;
        display: block !important;
      }
      #report_modal > div {
        box-shadow: none !important;
        max-height: none !important;
        border-radius: 0 !important;
      }
      #report_modal_body { overflow: visible !important; }
      #report_modal .print-btn { display: none !important; }
    }
  </style>`;

  let match;
  while ((match = styleRegex.exec(body)) !== null) {
    styles.push(match[0]);
  }
  const cleanBody = body.replace(styleRegex, '');

  const inlineScript = `
    (() => {
      ${actionEngineCode}
      ${gridActionsCode}
      ${selectActionsCode}
      ${formActionsCode}
      ${reportActionsCode}
    })();
  `;

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${title || 'WhatsFresh'}</title>
  <script src="https://unpkg.com/htmx.org@1.9.10"></script>
  <script>
    ${inlineScript}
  </script>
  ${fallbackUiStyles}
  ${styles.join('\n')}
</head>
<body>
  ${cleanBody}
</body>
</html>`;
}
