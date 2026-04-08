function escapeHtml(value = '') {
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

export function renderLoginPage({ routeInfo, pageStructure = null }) {
  const pageTitle = pageStructure?.pageInfo?.pageTitle || 'Login to WhatsFresh';
  const appName = routeInfo?.app_name || 'WhatsFresh';

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${escapeHtml(pageTitle)}</title>
  <script src="https://unpkg.com/htmx.org@1.9.10"></script>
  <style>
    :root {
      color-scheme: light;
      --bg: linear-gradient(135deg, #0f172a, #1d4ed8);
      --panel: rgba(255,255,255,0.96);
      --text: #132238;
      --muted: #5b7088;
      --brand: #0f62fe;
      --danger: #c62828;
      --line: #d9e3ee;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      display: grid;
      place-items: center;
      font-family: Inter, "Segoe UI", sans-serif;
      background: var(--bg);
      color: var(--text);
      padding: 24px;
    }
    .wf-login-shell {
      width: 100%;
      max-width: 420px;
      background: var(--panel);
      border-radius: 18px;
      box-shadow: 0 24px 60px rgba(15, 23, 42, 0.25);
      padding: 28px;
    }
    .wf-login-shell h1 {
      margin: 0 0 8px;
      font-size: 1.8rem;
    }
    .wf-login-shell p {
      margin: 0 0 20px;
      color: var(--muted);
    }
    .wf-field {
      display: grid;
      gap: 8px;
      margin-bottom: 14px;
    }
    .wf-field label {
      font-weight: 600;
      font-size: 0.95rem;
    }
    .wf-field input {
      width: 100%;
      padding: 12px 14px;
      border: 1px solid var(--line);
      border-radius: 12px;
      font: inherit;
    }
    .wf-submit {
      width: 100%;
      border: 0;
      border-radius: 12px;
      background: var(--brand);
      color: white;
      padding: 12px 16px;
      font: inherit;
      font-weight: 700;
      cursor: pointer;
    }
    .wf-submit[disabled] {
      opacity: 0.7;
      cursor: wait;
    }
    .wf-error {
      min-height: 20px;
      color: var(--danger);
      margin-top: 12px;
      font-size: 0.92rem;
    }
  </style>
</head>
<body>
  <main class="wf-login-shell">
    <h1>${escapeHtml(appName)}</h1>
    <p>${escapeHtml(pageTitle)}</p>
    <form id="login-form">
      <div class="wf-field">
        <label for="email">Email</label>
        <input id="email" name="email" type="email" autocomplete="username" required />
      </div>
      <div class="wf-field">
        <label for="password">Password</label>
        <input id="password" name="password" type="password" autocomplete="current-password" required />
      </div>
      <button class="wf-submit" id="login-submit" type="submit">Sign in</button>
      <div class="wf-error" id="login-error"></div>
    </form>
  </main>

  <script>
    const form = document.getElementById('login-form');
    const submitButton = document.getElementById('login-submit');
    const errorBox = document.getElementById('login-error');

    form.addEventListener('submit', async (event) => {
      event.preventDefault();
      errorBox.textContent = '';
      submitButton.disabled = true;

      const payload = {
        email: form.email.value.trim(),
        password: form.password.value
      };

      try {
        const response = await fetch('/api/auth/verify', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload)
        });

        const data = await response.json();

        if (!response.ok || !data.passwordMatches) {
          throw new Error(data.error || 'Invalid email or password');
        }

        window.location.assign(data.redirectTo || '/');
      } catch (error) {
        errorBox.textContent = error.message;
      } finally {
        submitButton.disabled = false;
      }
    });
  </script>
</body>
</html>`;
}
