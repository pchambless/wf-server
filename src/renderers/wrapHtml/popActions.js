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

        open: async (templateName, dropdownSlot) => {
          const scaffold = await ensurePopModalScaffold();
          const container = scaffold.container;
          const modal = scaffold.modal;

          if (!container || !modal) return;

          popModal._dropdownSlot = dropdownSlot;

          const response = await fetch("/api/hydrate", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ template_name: templateName })
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

        close: () => {
          const modal = document.getElementById("pop_modal");
          const container = document.getElementById("pop_container");
          if (modal) modal.classList.add("hidden");
          if (container) container.innerHTML = "";
          popModal._dropdownSlot = null;
        },

        refreshDropdown: async (newId) => {
          const slotName = popModal._dropdownSlot;
          if (!slotName) return;

          // Find the select element inside the dropdown wrapper
          const wrapper = document.querySelector('[data-dropdown-slot="' + slotName + '"]');
          if (!wrapper) return;

          // Derive template name from slot: f_locations_dd -> locations_dd
          const templateName = slotName.replace(/^f_/, "");

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
            await popModal.refreshDropdown(newId);
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
`;
