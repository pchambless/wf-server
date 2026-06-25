import { Router } from 'express';
import { callWorkflow } from '../utils/n8nClient.js';
import logger from '../utils/logger.js';

const router = Router();

router.post('/dml', async (req, res) => {
  const email = req.session?.current_user_email;
  if (!email) return res.status(401).json({ success: false, error: 'Unauthorized' });

  const { page_id, mode, ...formFields } = req.body;

  if (!page_id || !mode) {
    return res.status(400).json({ success: false, error: 'page_id and mode are required' });
  }

  // Strip empty f_id to prevent NaN in DML pk_val
  if (!formFields.f_id && formFields.f_id !== 0) {
    delete formFields.f_id;
  }

  logger.info('[api] Request', { path: '/api/dml', page_id, mode, email });

  try {
    const result = await callWorkflow('dml', {
      page_id,
      mode,
      user: email,
      ...formFields
    });

    // n8n webhook returns array; extract first item's result
    const raw = Array.isArray(result) ? result[0] : result;
    const dmlResult = raw?.result || raw;
    const parsed = typeof dmlResult === 'string' ? JSON.parse(dmlResult) : dmlResult;

    logger.info('[api] Response', {
      path: '/api/dml',
      success: parsed?.success,
      mode: parsed?.mode,
      page_id
    });

    if (parsed?.success) {
      res.json({ success: true, mode: parsed.mode, data: parsed.data });
    } else {
      res.status(422).json({ success: false, error: parsed?.error || 'DML failed' });
    }
  } catch (err) {
    logger.error('[api] Response', { path: '/api/dml', success: false, error: err.message });
    res.status(500).json({ success: false, error: 'Server error' });
  }
});

export default router;
