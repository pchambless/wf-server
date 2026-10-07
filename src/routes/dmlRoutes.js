import { Router } from 'express';
import { callWorkflow } from '../utils/n8nClient.js';
import logger from '../utils/logger.js';

const router = Router();

// Feedback (studio.pages id=102, the appbar Feedback button) no longer writes through the generic
// dml: every environment's feedback lands in ONE table (support.feedback on the dev droplet) via
// the feedback-intake workflow, which also posts the Slack notice (task 477). Same code
// everywhere: dev and local call their own n8n; prod sets FEEDBACK_INTAKE_URL to dev's webhook
// (prod n8n has no Slack credential and must not hold a login to dev's database).
const FEEDBACK_PAGE_ID = 102;
const SOURCE_ENV = process.env.APP_ENV || 'dev';
const FEEDBACK_INTAKE_URL = process.env.FEEDBACK_INTAKE_URL || '';

async function submitFeedback(email, fields) {
  const payload = {
    email,
    account_id: Number(fields.f_account_id) || 0,
    page_id: Number(fields.f_page_id),
    title: fields.f_title,
    category: fields.f_category,
    message: fields.f_message,
    source_env: SOURCE_ENV
  };

  if (!FEEDBACK_INTAKE_URL) {
    const result = await callWorkflow('feedback-intake', payload);
    return Array.isArray(result) ? result[0] : result;
  }

  const response = await fetch(FEEDBACK_INTAKE_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(process.env.N8N_WEBHOOK_SECRET ? { 'X-Webhook-Secret': process.env.N8N_WEBHOOK_SECRET } : {})
    },
    body: JSON.stringify(payload),
    signal: AbortSignal.timeout(15000)
  });
  if (!response.ok) throw new Error(`feedback-intake returned ${response.status}`);
  const result = await response.json();
  return Array.isArray(result) ? result[0] : result;
}

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

  if (Number(page_id) === FEEDBACK_PAGE_ID && mode === 'INSERT') {
    try {
      const saved = await submitFeedback(email, formFields);
      if (!saved?.success) throw new Error('feedback-intake did not confirm the save');
      return res.json({ success: true, mode: 'INSERT', data: { id: saved.id } });
    } catch (err) {
      logger.error('[api] feedback-intake failed', { error: err.message, source_env: SOURCE_ENV });
      return res.status(502).json({
        success: false,
        error: 'We could not send your feedback just now. Please try again in a minute.'
      });
    }
  }

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
