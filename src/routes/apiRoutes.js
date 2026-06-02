import { Router } from 'express';
import { handleLogin } from '../controllers/loginHandler.js';
import hydrateRoutes from './hydrateRoutes.js';
import actionRoutes from './actionRoutes.js';

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
router.use(hydrateRoutes);
router.use(actionRoutes);

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
