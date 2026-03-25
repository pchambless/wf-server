# WhatsFresh wf-server - Copilot Instructions

## Architecture

Express.js app (ESM modules) serving HTMX pages. All data flows through n8n webhooks — no direct database access ever.

```
src/
  app.js          Express init
  server.js       Entry point
  utils/
    n8nClient.js  All n8n calls go here
  routes/         Route handlers
  controller/     Business logic + HTMX renderers
  renderers/      Composite UI builders
```

## Code Style

- ESM only: `import/export` — never `require()`
- No comments unless asked
- No hardcoded values — config via `.env` or DB
- Modularize when files get large

## n8n Client Pattern

All data requests go through `n8nClient.js`:

```javascript
import { callWorkflow } from '../utils/n8nClient.js';

// Select widget HTML (for HTMX)
const optionsHtml = await callWorkflow('dd-query', {
  query: "SELECT * FROM whatsfresh.dd_accounts()",
  params: {},
  source: 'server'    // returns <option> HTML
});

// Run a report
const reportHtml = await callWorkflow('wf-report', {
  report: 'rpt-recipe',
  params: { product_id: 42 }
});
```

## HTMX Response Pattern

Controllers return HTML fragments, not JSON:

```javascript
export async function loadSelectWidget(req, res) {
  const html = await callWorkflow('dd-query', { ... });
  res.setHeader('Content-Type', 'text/html');
  res.send(html);
}
```

## What NOT To Do

- Never import `mysql2`, `pg`, or any DB driver directly
- Never call `https://n8n.whatsfresh.app/webhook/...` inline — always use `n8nClient.js`
- Never use CommonJS (`require`, `module.exports`)
- Never hardcode SQL in Express controllers
