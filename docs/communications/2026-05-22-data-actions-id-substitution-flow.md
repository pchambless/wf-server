# Trace: `{{id}}` Substitution in `data-actions`

**Date:** 2026-05-22  
**Author:** Copilot  
**Status:** Investigated

## Problem

Grid row click actions require `{{id}}` inside `data-actions` JSON to resolve to the clicked row id, but current output preserves the literal string `"{{id}}"`.

## End-to-End Flow (Current)

1. **wf-server page render path**
   - `renderPage()` calls n8n `page_structure` to get page metadata/components.
   - `renderPage()` then calls n8n `hydrate-guide` with the page template name and receives hydrated HTML.
   - Slot placeholders are replaced with wrapper divs via `buildHtmxDiv()`.
   - The final HTML is wrapped by `wrapHtml()` and sent to browser.

2. **Component hydration path**
   - `buildHtmxDiv()` emits HTMX attributes and optional action metadata (`data-action-*`) for component wrappers.
   - Wrapper metadata is serialized with `JSON.stringify(...)` and is not template-expanded.

3. **API hydrate path**
   - `/api/hydrate` (in `apiRoutes.js`) forwards `template_name` to n8n `hydrate-guide`.
   - Returned HTML is relayed directly to the client.

4. **Client path**
   - `wrapHtml()` injects HTMX and page shell only.
   - No client-side `{{...}}` template substitution logic exists in wf-server.

## Where `{{id}}` Can Be Replaced

### What wf-server currently can/cannot do

- wf-server does **not** currently parse hydrated HTML for row-level JSON templates.
- wf-server does **not** have a row object context when serializing `data-action-*` metadata.
- `buildHtmxDiv()` and `wrapHtml()` provide structure/shell behavior, not row template interpolation.

### Correct substitution point

`{{id}}` should be resolved where row data is available: **in n8n workflow generation (hydrate-guide/raw-json stage)** when building each row/action payload.

## Architecture Decision

### Recommended

Perform substitution in n8n (`hydrate-guide` / `raw-json`) when rows are materialized, e.g. build per-row action JSON using real row fields (`id`) before HTML/JSON is returned to wf-server.

### Not recommended as primary fix

- **wf-server rendering layer**: lacks reliable row-level context and would require brittle HTML/JSON parsing.
- **browser runtime substitution**: adds duplicated template semantics to client and makes action behavior dependent on DOM conventions.

## Conclusion

The current code path confirms there is no existing wf-server template substitution mechanism for `{{id}}` in action JSON. The fix should be implemented in n8n at row construction time so `data-actions` arrives already populated with concrete ids.

## Code References

- `/tmp/workspace/pchambless/wf-server/src/renderers/renderPage.js`
- `/tmp/workspace/pchambless/wf-server/src/renderers/buildHtmxDiv.js`
- `/tmp/workspace/pchambless/wf-server/src/renderers/wrapHtml.js`
- `/tmp/workspace/pchambless/wf-server/src/routes/apiRoutes.js`
- `/tmp/workspace/pchambless/wf-server/src/utils/n8nClient.js`
