function escapeHtml(value = '') {
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function toLabel(value = '') {
  return String(value)
    .split(/[-_\s]+/)
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(' ');
}

export function renderDashboardPage({ currentRoute, routeInfo, sessionUser, allRoutes = [], pageStructure = null }) {
  const appName = routeInfo?.app_name || 'whatsfresh';
  const pageTitle = routeInfo?.page_name ? toLabel(routeInfo.page_name) : 'Dashboard';
  const userName = [sessionUser?.first_name, sessionUser?.last_name].filter(Boolean).join(' ') || sessionUser?.email || 'there';
  const appRoutes = allRoutes
    .filter((item) => item.app_name === appName && item.route !== currentRoute)
    .sort((a, b) => a.page_name.localeCompare(b.page_name));

  const cards = appRoutes.length
    ? appRoutes.map((item) => `
        <a class="wf-card" href="${escapeHtml(item.route)}">
          <span class="wf-card__eyebrow">${escapeHtml(toLabel(item.app_name))}</span>
          <strong>${escapeHtml(toLabel(item.page_name))}</strong>
          <span>${escapeHtml(item.route)}</span>
        </a>
      `).join('')
    : '<div class="wf-empty">More pages will appear here as they are published.</div>';

  const componentCount = Array.isArray(pageStructure?.components) ? pageStructure.components.length : 0;

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${escapeHtml(toLabel(appName))} ${escapeHtml(pageTitle)}</title>
  <script src="https://unpkg.com/htmx.org@1.9.10"></script>
  <style>
    :root {
      color-scheme: light;
      --bg: #f4f7fb;
      --panel: #ffffff;
      --ink: #132238;
      --muted: #58708a;
      --line: #d6e0ea;
      --brand: #0f62fe;
      --brand-soft: #e8f0ff;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: Inter, "Segoe UI", sans-serif;
      background: var(--bg);
      color: var(--ink);
    }
    .wf-shell {
      max-width: 1120px;
      margin: 0 auto;
      padding: 32px 20px 48px;
    }
    .wf-hero {
      background: linear-gradient(135deg, #132238, #1f4b99);
      color: white;
      border-radius: 18px;
      padding: 28px;
      margin-bottom: 24px;
      box-shadow: 0 18px 40px rgba(19, 34, 56, 0.18);
    }
    .wf-hero h1 {
      margin: 0 0 8px;
      font-size: 2rem;
    }
    .wf-hero p {
      margin: 0;
      color: rgba(255, 255, 255, 0.88);
    }
    .wf-meta {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
      gap: 16px;
      margin: 24px 0;
    }
    .wf-stat, .wf-panel {
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 16px;
      padding: 18px;
    }
    .wf-stat strong {
      display: block;
      font-size: 1.6rem;
      margin-top: 6px;
    }
    .wf-stat span,
    .wf-panel p,
    .wf-card span,
    .wf-empty {
      color: var(--muted);
    }
    .wf-section-title {
      margin: 0 0 12px;
      font-size: 1.1rem;
    }
    .wf-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
      gap: 16px;
    }
    .wf-card {
      display: flex;
      flex-direction: column;
      gap: 8px;
      padding: 18px;
      text-decoration: none;
      background: var(--panel);
      color: var(--ink);
      border: 1px solid var(--line);
      border-radius: 16px;
      transition: transform 120ms ease, box-shadow 120ms ease;
    }
    .wf-card:hover {
      transform: translateY(-2px);
      box-shadow: 0 12px 28px rgba(15, 98, 254, 0.12);
    }
    .wf-card__eyebrow {
      color: var(--brand);
      font-size: 0.78rem;
      font-weight: 700;
      text-transform: uppercase;
      letter-spacing: 0.04em;
    }
    .wf-empty {
      padding: 18px;
      background: var(--panel);
      border: 1px dashed var(--line);
      border-radius: 16px;
    }
  </style>
</head>
<body>
  <main class="wf-shell">
    <section class="wf-hero">
      <h1>${escapeHtml(toLabel(appName))} Dashboard</h1>
      <p>Welcome back, ${escapeHtml(userName)}.</p>
    </section>

    <section class="wf-meta">
      <div class="wf-stat">
        <span>Current route</span>
        <strong>${escapeHtml(currentRoute)}</strong>
      </div>
      <div class="wf-stat">
        <span>Available pages</span>
        <strong>${appRoutes.length}</strong>
      </div>
      <div class="wf-stat">
        <span>Configured components</span>
        <strong>${componentCount}</strong>
      </div>
    </section>

    <section class="wf-panel">
      <h2 class="wf-section-title">Open a page</h2>
      <div class="wf-grid">${cards}</div>
    </section>
  </main>
</body>
</html>`;
}
