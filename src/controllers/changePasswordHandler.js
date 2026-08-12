import { callWorkflow } from '../utils/n8nClient.js';
import { escSqlString } from '../utils/sqlEscape.js';
import logger from '../utils/logger.js';

export async function handleChangePassword(req, res) {
  const email = req.session?.current_user_email;
  if (!email) return res.status(401).json({ success: false, message: 'Authentication required' });

  const { old_password, new_password, confirm_password } = req.body;

  if (!old_password || !new_password || !confirm_password) {
    return res.status(400).json({ success: false, message: 'All fields are required' });
  }

  if (new_password !== confirm_password) {
    return res.status(400).json({ success: false, message: 'New passwords do not match' });
  }

  if (new_password.length < 8) {
    return res.status(400).json({ success: false, message: 'Password must be at least 8 characters' });
  }

  try {
    const result = await callWorkflow('server-query', {
      query: `SELECT * FROM whatsfresh.api_change_password(${escSqlString(email)}, ${escSqlString(old_password)}, ${escSqlString(new_password)})`,
      params: {},
      source: 'change-password'
    });

    const row = Array.isArray(result) ? result[0] : result;

    if (!row?.success) {
      logger.warn('[api] Response', { path: '/api/auth/change-password', success: false, reason: row?.error_message });
      return res.status(400).json({ success: false, message: row?.error_message || 'Password change failed' });
    }

    logger.info('[api] Response', { path: '/api/auth/change-password', success: true, email });
    return res.json({ success: true, redirectTo: '/wf-dashboard' });
  } catch (err) {
    logger.error('[api] Response', { path: '/api/auth/change-password', success: false, error: err.message });
    return res.status(500).json({ success: false, message: 'Password service unavailable' });
  }
}
