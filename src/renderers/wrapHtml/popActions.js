export const popActionsCode = `
      const ensurePopModalScaffold = async () => {
        const existingModal = document.getElementById("pop_modal");
        const existingContainer = document.getElementById("pop_container");
        if (existingModal && existingContainer) {
          return { modal: existingModal, container: existingContainer };
        }

        const scaffoldResponse = await fetch("/api/hydrate", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ template_name: "pop_modal" })
        });

        if (!scaffoldResponse.ok) {
          throw new Error("Failed to load pop_modal scaffold");
        }

        const scaffoldHtml = await scaffoldResponse.text();
        document.body.insertAdjacentHTML("beforeend", scaffoldHtml);

        return {
          modal: document.getElementById("pop_modal"),
          container: document.getElementById("pop_container")
        };
      };

      const popModal = {
        _onSuccess: null,
        _dropdownSlot: null,
        _refreshTargets: null,

        open: async (templateName, dropdownSlot, refreshTargets) => {
          const scaffold = await ensurePopModalScaffold();
          const container = scaffold.container;
          const modal = scaffold.modal;

          if (!container || !modal) return;

          popModal._dropdownSlot = dropdownSlot;
          popModal._refreshTargets = refreshTargets || null;

          // Quick-add forms hydrate via c_getval('<entity>_id') the same way the
          // main Add New button's inline form does (see wrapHtml/index.js) - without
          // explicitly nulling that context key here, a stale id left over from
          // editing/adding that entity elsewhere makes this "new" form come back
          // pre-populated with the last row instead of blank.
          const contextKey = templateName.replace(/_form$/, "") + "_id";

          const response = await fetch("/api/hydrate", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ template_name: templateName, mode: "INSERT", [contextKey]: null })
          });

          const formHtml = await response.text();
          container.innerHTML = formHtml;

          if (window.htmx) window.htmx.process(container);

          const form = container.querySelector("form");
          if (form) {
            form.id = "pop_form_element";
          }

          const entityName = templateName.replace(/_form$/, "").replace(/_/g, " ");
          const title = "Add " + entityName;
          const modalTitle = document.getElementById("pop_modal_title");
          if (modalTitle) {
            modalTitle.textContent = title;
          }

          modal.classList.remove("hidden");
        },

        // Read-only content (e.g. a page's help_text) in the same scaffold. The
        // header Save button submits #pop_form_element, which doesn't exist here,
        // so hide it; close() restores it for the next form open.
        openContent: async (title, html) => {
          const scaffold = await ensurePopModalScaffold();
          if (!scaffold.container || !scaffold.modal) return;

          scaffold.container.innerHTML = html;
          const modalTitle = document.getElementById("pop_modal_title");
          if (modalTitle) modalTitle.textContent = title;
          const saveBtn = scaffold.modal.querySelector('button[form="pop_form_element"]');
          if (saveBtn) saveBtn.style.display = "none";

          scaffold.modal.classList.remove("hidden");
        },

        close: () => {
          const modal = document.getElementById("pop_modal");
          const container = document.getElementById("pop_container");
          const saveBtn = modal?.querySelector('button[form="pop_form_element"]');
          if (saveBtn) saveBtn.style.display = "";
          if (modal) modal.classList.add("hidden");
          if (container) container.innerHTML = "";
          popModal._dropdownSlot = null;
          popModal._refreshTargets = null;
        },

        // Non-dropdown quick-adds (e.g. "+ Add Worker" next to a checkbox list,
        // not a <select>) refresh a named component instead. These targets are
        // NOT standalone htmx components - {{slot:X}} composes them into the
        // parent template's HTML once at render time, with no hx-post/hx-trigger
        // of their own, so htmx.trigger(el, 'refresh-component') is a silent
        // no-op here (confirmed live 2026-10-05 - nothing is listening). Fetch
        // and swap directly by template name instead, same as refreshDropdown
        // does for a <select>. worker_checkboxes specifically needs
        // initWorkerPicker() re-run afterward - its checked state and
        // change-listener live on the OUTER wrapper, which survives the
        // innerHTML swap, but the pre-check-from-f_workers step only runs when
        // initWorkerPicker() is called.
        refreshTargets: async (targets) => {
          for (const id of targets) {
            const el = document.getElementById(id);
            if (!el) continue;

            const response = await fetch("/api/hydrate", {
              method: "POST",
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify({ template_name: id })
            });
            if (!response.ok) continue;

            el.innerHTML = await response.text();
            if (window.htmx) window.htmx.process(el);

            if (id === "worker_checkboxes" && typeof initWorkerPicker === "function") {
              initWorkerPicker();
            }
          }
        },

        refreshDropdown: async (newId) => {
          const slotName = popModal._dropdownSlot;
          if (!slotName) return;

          // Find the select element inside the dropdown wrapper
          const wrapper = document.querySelector('[data-dropdown-slot="' + slotName + '"]');
          if (!wrapper) return;

          // Read the template name the renderer already emitted, rather than
          // rebuilding it from the slot naming convention. Every select path
          // (buildSelectWidget, buildHtmxDiv) sets
          // data-template-name, and htmx swaps the div's innerHTML, so the
          // attribute survives hydration.
          const widget = wrapper.querySelector("[data-template-name]");
          let templateName = widget && widget.dataset.templateName;
          if (!templateName) {
            templateName = slotName.replace(/^f_/, "");
            console.warn(
              "popModal.refreshDropdown: no data-template-name in slot '" +
                slotName + "', falling back to name derivation -> " + templateName
            );
          }

          // Re-hydrate the dropdown
          const response = await fetch("/api/hydrate", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ template_name: templateName })
          });

          if (!response.ok) return;

          const newHtml = await response.text();

          // Preserve the + button, only replace the select
          const addBtn = wrapper.querySelector(".dd-add-btn");
          const selectEl = wrapper.querySelector("select");
          
          if (selectEl) {
            // Create temp container to parse new HTML
            const temp = document.createElement("div");
            temp.innerHTML = newHtml;
            const newSelect = temp.querySelector("select");
            if (newSelect) {
              selectEl.replaceWith(newSelect);
              // Auto-select the new item
              if (newId) {
                newSelect.value = String(newId);
              }
            }
          } else {
            // No existing select, just inject before the button
            if (addBtn) {
              addBtn.insertAdjacentHTML("beforebegin", newHtml);
            } else {
              wrapper.innerHTML = newHtml;
            }
          }
        }
      };

      window.popModal = popModal;

      // --- Pop Modal Form Submit Handler ---
      document.addEventListener("submit", async (e) => {
        const form = e.target;
        if (!form || form.id !== "pop_form_element") return;
        e.preventDefault();

        const pageId = form.dataset.pageId || window.__popPageId;

        if (!pageId) {
          alert("Error: page context not available for quick add");
          return;
        }

        const formData = new FormData(form);
        const payload = { page_id: parseInt(pageId), mode: "INSERT" };

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
            const newId = result.data?.id;
            if (popModal._dropdownSlot) {
              await popModal.refreshDropdown(newId);
            }
            if (popModal._refreshTargets) {
              await popModal.refreshTargets(popModal._refreshTargets);
            }
            popModal.close();
          } else {
            const errMsg = typeof result.error === "object" ? JSON.stringify(result.error) : (result.error || "Save failed");
            alert(errMsg);
          }
        } catch (err) {
          alert("Save failed: " + err.message);
        }
      });

      // Close handlers for pop modal
      document.addEventListener("click", (e) => {
        if (e.target instanceof Element && e.target.closest(".pop-modal-close")) {
          popModal.close();
        }
      });
      document.addEventListener("keydown", (e) => {
        if (e.key === "Escape") {
          const popModalEl = document.getElementById("pop_modal");
          if (popModalEl && !popModalEl.classList.contains("hidden")) {
            popModal.close();
          }
        }
      });

      // --- dd-add-btn click handler ---
      document.addEventListener("click", (e) => {
        const btn = e.target instanceof Element ? e.target.closest(".dd-add-btn") : null;
        if (!btn) return;

        const formTemplate = btn.dataset.popForm;
        const popPageId = btn.dataset.popPageId;
        const dropdownSlot = btn.dataset.dropdownSlot;

        if (!formTemplate) return;

        window.__popPageId = popPageId;
        popModal.open(formTemplate, dropdownSlot);
      });

      // --- Best By Date auto-calc on Batch Date change ---
      document.addEventListener("change", (e) => {
        if (!(e.target instanceof Element) || e.target.id !== "f_event_date") return;
        const bestByDate = document.getElementById("f_best_by_date");
        const bestByDays = document.getElementById("f_best_by_days");
        if (!bestByDate || !bestByDays) return;
        const days = parseInt(bestByDays.value);
        if (e.target.value && days) {
          const d = new Date(e.target.value + "T00:00:00");
          d.setDate(d.getDate() + days);
          bestByDate.value = d.toISOString().split("T")[0];
        }
      });

      // --- Auto-generate tooltips for dd-add-btn ---
      document.addEventListener("mouseover", (e) => {
        const btn = e.target instanceof Element ? e.target.closest(".dd-add-btn") : null;
        if (!btn || btn.title) return;
        const formName = btn.dataset.popForm || "";
        const entity = formName.replace(/_form$/, "").replace(/_/g, " ");
        btn.title = "Add new " + entity;
      });
`;
