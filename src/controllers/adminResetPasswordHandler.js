import { callWorkflow } from '../utils/n8nClient.js';
import { escSqlString } from '../utils/sqlEscape.js';
import logger from '../utils/logger.js';

export async function handleAdminResetPassword(req, res) {
  const email = req.session?.current_user_email;
  if (!email) return res.status(401).json({ success: false, message: 'Authentication required' });

  const { user_id, new_password } = req.body;

  if (!user_id || !new_password) {
    return res.status(400).json({ success: false, message: 'user_id and new_password are required' });
  }

  if (new_password.length < 8) {
    return res.status(400).json({ success: false, message: 'Password must be at least 8 characters' });
  }

  try {
    const roleResult = await callWorkflow('server-query', {
      query: `SELECT role FROM whatsfresh.users WHERE email = ${escSqlString(email)}`,
      params: {},
      source: 'admin-reset-password'
    });
    const roleRow = Array.isArray(roleResult) ? roleResult[0] : roleResult;

    if (roleRow?.role !== 1) {
      logger.warn('[api] Response', { path: '/api/admin/reset-password', success: false, reason: 'not_staff', email });
      return res.status(403).json({ success: false, message: 'Staff access required' });
    }

    const result = await callWorkflow('server-query', {
      query: `SELECT * FROM whatsfresh.api_admin_reset_password(${parseInt(user_id, 10)}, ${escSqlString(new_password)}, ${escSqlString(email)})`,
      params: {},
      source: 'admin-reset-password'
    });
    const row = Array.isArray(result) ? result[0] : result;

    if (!row?.success) {
      logger.warn('[api] Response', { path: '/api/admin/reset-password', success: false, reason: row?.error_message });
      return res.status(400).json({ success: false, message: row?.error_message || 'Reset failed' });
    }

    logger.info('[api] Response', { path: '/api/admin/reset-password', success: true, user_id, reset_by: email });
    return res.json({ success: true });
  } catch (err) {
    logger.error('[api] Response', { path: '/api/admin/reset-password', success: false, error: err.message });
    return res.status(500).json({ success: false, message: 'Reset service unavailable' });
  }
}
