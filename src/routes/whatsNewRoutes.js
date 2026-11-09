import { Router } from 'express';
import { callWorkflow } from '../utils/n8nClient.js';
import logger from '../utils/logger.js';

const router = Router();

// What's New (task 846): the appbar button shows the release notes of the last few shipped releases.
// The notes live in the agile schema on the dev droplet, so the whats-new workflow (dev n8n, read-only) builds the HTML.
// Same pattern as feedback: dev and local call their own n8n; prod sets WHATS_NEW_URL to dev's webhook
// (https://n8n.whatsfresh.app/webhook/whats-new) and sends the shared webhook secret, so prod needs no login to dev's database.
const WHATS_NEW_URL = process.env.WHATS_NEW_URL || '';
const UNAVAILABLE = '<p>What\'s New is not available right now. Please try again later.</p>';

async function fetchWhatsNew() {
  if (!WHATS_NEW_URL) {
    const result = await callWorkflow('whats-new', {});
    return (Array.isArray(result) ? result[0] : result)?.html;
  }
  const response = await fetch(WHATS_NEW_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(process.env.N8N_WEBHOOK_SECRET ? { 'X-Webhook-Secret': process.env.N8N_WEBHOOK_SECRET } : {})
    },
    body: '{}',
    signal: AbortSignal.timeout(10000)
  });
  if (!response.ok) throw new Error(`whats-new returned ${response.status}`);
  const result = await response.json();
  return (Array.isArray(result) ? result[0] : result)?.html;
}

router.get('/whats-new', async (req, res) => {
  if (!req.session?.current_user_email) return res.status(401).type('text').send('Unauthorized');
  try {
    const html = await fetchWhatsNew();
    res.type('html').send(html || UNAVAILABLE);
  } catch (err) {
    logger.error('[api] whats-new failed', { error: err.message });
    res.type('html').send(UNAVAILABLE);
  }
});

export default router;
