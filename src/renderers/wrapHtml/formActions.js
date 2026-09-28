export const formActionsCode = `
      // --- Inline Form Submit Handler ---
      document.addEventListener("submit", async (e) => {
        const form = e.target;
        if (!form || form.id !== "inline_form_element") return;
        e.preventDefault();

        const mode = window.contextStore?.mode || "INSERT";
        const pageId = window.__pageContext?.pageId || window.contextStore?.page_id;

        if (!pageId) {
          alert("Error: page context not available");
          return;
        }

        const formData = new FormData(form);
        const payload = { page_id: pageId, mode };

        for (const [key, value] of formData.entries()) {
          payload[key] = value;
        }

        try {
          const response = await fetch("/api/dml", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(payload)
          });

          const result = await response.json();

          if (result.success) {
            const panel = document.getElementById("inline_form_panel");
            if (panel) panel.classList.add("hidden");

            // Refresh just the grid instead of reloading the whole page - same
            // refreshComponents mechanism dml_direct buttons already use. After
            // the grid re-hydrates, scroll back to the row just saved instead of
            // snapping to the top. Falls back to a full reload if the page never
            // declared a grid (no gridComponentId in __pageContext).
            const gridId = window.__pageContext?.gridComponentId;
            const contextKey = window.__pageContext?.contextKey || "id";
            const savedId = window.contextStore?.[contextKey];
            const grid = gridId && document.getElementById(gridId);

            if (grid && window.htmx) {
              const onSwap = (evt) => {
                if (evt.target !== grid) return;
                grid.removeEventListener("htmx:afterSwap", onSwap);
                if (savedId) {
                  const row = grid.querySelector('[data-row-id="' + savedId + '"]');
                  if (row) row.scrollIntoView({ behavior: "smooth", block: "center" });
                }
              };
              grid.addEventListener("htmx:afterSwap", onSwap);
              refreshComponents([gridId]);
            } else {
              window.location.reload();
            }
          } else {
            const errMsg = typeof result.error === 'object' ? JSON.stringify(result.error) : (result.error || "Save failed");
            alert(errMsg);
          }
        } catch (err) {
          alert("Save failed: " + err.message);
        }
      });

      // --- Inline Form Close ---
      document.addEventListener("click", (e) => {
        if (e.target instanceof Element && e.target.closest(".inline-form-close")) {
          const panel = document.getElementById("inline_form_panel");
          if (panel) panel.classList.add("hidden");
        }
      });
`;
