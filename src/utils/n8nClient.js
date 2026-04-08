const BASE_URL = process.env.N8N_BASE_URL || 'https://n8n.whatsfresh.app';

export { BASE_URL as N8N_BASE };

export async function callWorkflow(webhookPath, body = {}) {
  const url = `${BASE_URL}/webhook/${webhookPath}`;

  let response;
  try {
    response = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body)
    });
  } catch (err) {
    throw new Error(`n8n unreachable [${webhookPath}]: ${err.message}`);
  }

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`n8n error [${webhookPath}] ${response.status}: ${text}`);
  }

  const contentType = response.headers.get('content-type') || '';
  if (contentType.includes('text/html')) {
    return response.text();
  }

  return response.json();
}
