export const formActionsCode = `
      const ensureModalScaffold = async () => {
        const existingModal = document.getElementById("form_modal");
        const existingContainer = document.getElementById("form_container");
        if (existingModal && existingContainer) {
          return { modal: existingModal, container: existingContainer };
        }

        const scaffoldResponse = await fetch("/api/hydrate", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ template_name: "form_modal" })
        });

        if (!scaffoldResponse.ok) {
          throw new Error("Failed to load form_modal scaffold");
        }

        const scaffoldHtml = await scaffoldResponse.text();
        document.body.insertAdjacentHTML("beforeend", scaffoldHtml);

        return {
          modal: document.getElementById("form_modal"),
          container: document.getElementById("form_container")
        };
      };

      const formModal = {
        open: async (templateName, hydrateData) => {
          const scaffold = await ensureModalScaffold();
          const container = scaffold.container;
          const modal = scaffold.modal;

          if (!container || !modal) {
            return;
          }

          const response = await fetch("/api/hydrate", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ template_name: templateName, ...hydrateData })
          });

          const formHtml = await response.text();
          container.innerHTML = formHtml;

          if (window.htmx) window.htmx.process(container);

          const form = container.querySelector("form");
          if (form) {
            form.id = "form_element";
          }

          const mode = hydrateData?.mode || window.contextStore?.mode || "INSERT";
          // Sync contextStore so downstream code sees the correct mode
          window.contextStore = { ...(window.contextStore || {}), mode };
          const entityName = templateName.replace(/_form$/, "").replace(/_/g, " ");
          const nameField = form?.querySelector('[data-field="name"]');
          const displayName = nameField?.value || "";
          const title = mode === "UPDATE"
            ? \`UPDATE \${entityName}: \${displayName}\`
            : \`INSERT \${entityName}\`;
          const modalTitle = document.getElementById("modal_title");
          if (modalTitle) {
            modalTitle.textContent = title;
          }

          modal.classList.remove("hidden");

          // Initialize worker picker if present in this form
          if (container.querySelector('#worker_checkboxes') && typeof initWorkerPicker === 'function') {
            initWorkerPicker();
          }
        },

        close: () => {
          const modal = document.getElementById("form_modal");
          const container = document.getElementById("form_container");
          if (modal) {
            modal.classList.add("hidden");
          }
          if (container) {
            container.innerHTML = "";
          }
        }
      };

      window.formModal = formModal;

      // --- Form Submit Handler ---
      document.addEventListener("submit", async (e) => {
        const form = e.target;
        if (!form || form.id !== "form_element") return;
        e.preventDefault();

        const mode = window.contextStore?.mode || "INSERT";
        const pageId = window.__pageContext?.pageId || window.contextStore?.page_id;

        if (!pageId) {
          alert("Error: page context not available");
          return;
        }

        // Collect all form fields
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
            formModal.close();
            window.location.reload();
          } else {
            const errMsg = typeof result.error === 'object' ? JSON.stringify(result.error) : (result.error || "Save failed");
            alert(errMsg);
          }
        } catch (err) {
          alert("Save failed: " + err.message);
        }
      });

      document.addEventListener("click", (e) => {
        if (e.target instanceof Element && e.target.closest(".modal-close")) {
          formModal.close();
        }
      });
      document.addEventListener("keydown", (e) => {
        if (e.key === "Escape") formModal.close();
      });
`;
