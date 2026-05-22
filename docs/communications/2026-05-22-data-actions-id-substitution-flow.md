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

## Updated Requirement

The selected row value should be persisted by calling the `n8n.setvals` workflow rather than relying on wf-server to perform inline row-template substitution.

## Where the Row Id Should Flow

### What wf-server currently can/cannot do

- wf-server does **not** currently parse hydrated HTML for row-level JSON templates.
- wf-server does **not** have a row object context when serializing `data-action-*` metadata.
- `buildHtmxDiv()` and `wrapHtml()` provide structure/shell behavior, not row template interpolation.

### Correct persistence point

The row id should be sent as the action value and persisted through **`n8n.setvals`** so later workflow steps can read it from n8n-managed state.

## Architecture Decision

### Recommended

Use wf-server as a thin bridge:

1. Browser click action posts the selected value to `/api/setvals`
2. wf-server forwards that payload plus the session email to `n8n.setvals`
3. Later hydrate/render workflow calls consume the stored value from n8n state

### Not recommended as primary fix

- **wf-server rendering layer**: still lacks reliable row-level context for server-side HTML interpolation.
- **literal `{{id}}` values**: they should not be left unresolved in stored action payloads if the goal is to set workflow state.

## Conclusion

The corrected flow is to send the selected row id through wf-server into `n8n.setvals`, not to rely on wf-server HTML rendering to substitute `{{id}}` directly.

## Code References

- `/tmp/workspace/pchambless/wf-server/src/renderers/renderPage.js`
- `/tmp/workspace/pchambless/wf-server/src/renderers/buildHtmxDiv.js`
- `/tmp/workspace/pchambless/wf-server/src/renderers/wrapHtml.js`
- `/tmp/workspace/pchambless/wf-server/src/routes/apiRoutes.js`
- `/tmp/workspace/pchambless/wf-server/src/utils/n8nClient.js`
