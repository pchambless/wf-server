import { actionEngineCode } from './actionEngine.js';
import { gridActionsCode } from './gridActions.js';
import { selectActionsCode } from './selectActions.js';
import { formActionsCode } from './formActions.js';

export function wrapHtml(title, body) {
  const styleRegex = /<style[^>]*>[\s\S]*?<\/style>/gi;
  const styles = [];

  const fallbackUiStyles = `<style>
    .hidden { display: none !important; }
    .wf-slot-actions {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      margin: 8px 0;
    }
    .wf-slot-actions .wf-slot-action-btn {
      border: 0;
      border-radius: 8px;
      padding: 8px 24px;
      background: #0891b2;
      color: #ffffff;
      cursor: pointer;
    }
    .wf-slot-actions .wf-slot-action-btn:hover {
      background: #dcfce7;
      color: #1f2937;
    }
    .wf-slot-actions .wf-slot-action-btn:focus-visible {
      outline: 2px solid #0891b2;
      outline-offset: 2px;
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
