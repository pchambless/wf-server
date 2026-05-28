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
            body: JSON.stringify({ template_name: templateName })
          });

          const formHtml = await response.text();
          container.innerHTML = formHtml;

          if (window.htmx) window.htmx.process(container);

          const form = container.querySelector("form");
          if (form) {
            form.id = "form_element";
            form.querySelectorAll("[data-field]").forEach(field => {
              const key = field.getAttribute("data-field");
              if (key in hydrateData) {
                field.value = hydrateData[key] || "";
              }
            });
          }

          const mode = window.contextStore?.mode || "INSERT";
          const entityName = templateName.replace(/_form$/, "").replace(/_/g, " ");
          const title = mode === "UPDATE"
            ? \`UPDATE \${entityName}: \${hydrateData.name || ""}\`
            : \`INSERT \${entityName}\`;
          const modalTitle = document.getElementById("modal_title");
          if (modalTitle) {
            modalTitle.textContent = title;
          }

          modal.classList.remove("hidden");
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

      document.addEventListener("click", (e) => {
        if (e.target instanceof Element && e.target.closest(".modal-close")) {
          formModal.close();
        }
      });
      document.addEventListener("keydown", (e) => {
        if (e.key === "Escape") formModal.close();
      });
`;
