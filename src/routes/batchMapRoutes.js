import { Router } from 'express';
import { callWorkflow } from '../utils/n8nClient.js';
import logger from '../utils/logger.js';

const router = Router();

router.post('/batch-map', async (req, res) => {
  const email = req.session?.current_user_email;
  if (!email) return res.status(401).json({ success: false, error: 'Unauthorized' });

  const { mode, source_batch_id, map_id } = req.body;

  if (!mode) {
    return res.status(400).json({ success: false, error: 'mode is required' });
  }

  logger.info('[api] Request', { path: '/api/batch-map', mode, source_batch_id, map_id, email });

  try {
    const result = await callWorkflow('dml-batch-map', {
      mode,
      source_batch_id,
      map_id,
      user: email
    });

    const raw = Array.isArray(result) ? result[0] : result;
    const dmlResult = raw?.result || raw;
    const parsed = typeof dmlResult === 'string' ? JSON.parse(dmlResult) : dmlResult;

    logger.info('[api] Response', { path: '/api/batch-map', success: parsed?.success, mode });

    if (parsed?.success) {
      res.json({ success: true, mode: parsed.mode, data: parsed.data });
    } else {
      res.status(422).json({ success: false, error: parsed?.error || 'Batch map operation failed' });
    }
  } catch (err) {
    logger.error('[api] Response', { path: '/api/batch-map', success: false, error: err.message });
    res.status(500).json({ success: false, error: 'Server error' });
  }
});

export default router;
