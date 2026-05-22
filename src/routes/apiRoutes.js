import { Router } from 'express';
import { handleLogin } from '../controllers/loginHandler.js';
import { callWorkflow } from '../utils/n8nClient.js';

const router = Router();

function getSessionEmail(req) {
  return req.session?.current_user_email;
}

function requireSessionEmail(req, res) {
  const email = getSessionEmail(req);
  if (!email) {
    res.status(401).json({ error: 'Authentication required' });
    return null;
  }
  return email;
}

router.post('/auth/login', handleLogin);

router.post('/hydrate', async (req, res) => {
  const { template_name } = req.body;
  const result = await callWorkflow('hydrate-guide', {
    template_name, source: 'wf-server', format: 'html'
  });
  const html = typeof result === 'string' ? result : result?.html || result?.[0]?.html || '';
  res.type('html').send(html);
});

router.post('/setvals', async (req, res) => {
  const email = requireSessionEmail(req, res);
  if (!email) return;

  try {
    const result = await callWorkflow('setvals', { ...req.body, email });
    res.json(result ?? { ok: true });
  } catch (error) {
    res.status(502).json({ error: error.message || 'Failed to set values' });
  }
});

router.post('/clearvals', async (req, res) => {
  const email = requireSessionEmail(req, res);
  if (!email) return;

  try {
    const result = await callWorkflow('clearvals', { ...req.body, email });
    res.json(result ?? { ok: true });
  } catch (error) {
    res.status(502).json({ error: error.message || 'Failed to clear values' });
  }
});

export default router;
