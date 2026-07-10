import { callWorkflow } from '../utils/n8nClient.js';
import logger from '../utils/logger.js';

export async function handleRegister(req, res) {
  const { first_name, last_name, email, password, confirm_password, company_name, zip_code, description, street_address, city, state_code, url } = req.body;

  logger.info('[api] Request', {
    path: '/api/auth/register',
    body: { email, first_name, last_name, company_name, zip_code, password: '[REDACTED]' }
  });

  // Validation
  if (!first_name || !last_name || !email || !password || !company_name || !zip_code) {
    return res.status(400).json({ success: false, message: 'All fields are required' });
  }

  if (password !== confirm_password) {
    return res.status(400).json({ success: false, message: 'Passwords do not match' });
  }

  if (password.length < 8) {
    return res.status(400).json({ success: false, message: 'Password must be at least 8 characters' });
  }

  try {
    const esc = (val) => val ? `'${val.replace(/'/g, "''")}'` : 'NULL';
    const result = await callWorkflow('server-query', {
      query: `SELECT * FROM whatsfresh.api_register_user(${esc(email)}, ${esc(password)}, ${esc(first_name)}, ${esc(last_name)}, ${esc(company_name)}, ${esc(zip_code)}, ${esc(description)}, ${esc(street_address)}, ${esc(city)}, ${esc(state_code)}, ${esc(url)})`,
      params: {},
      source: 'register'
    });

    const row = Array.isArray(result) ? result[0] : result;

    if (!row?.success) {
      logger.warn('[api] Response', {
        path: '/api/auth/register',
        success: false,
        reason: row?.error_message || 'registration_failed'
      });
      return res.status(400).json({ success: false, message: row?.error_message || 'Registration failed' });
    }

    // Auto-login: set session
    await callWorkflow('setvals', {
      email,
      vals: [{ param_name: 'account_id', param_val: String(row.account_id) }]
    });

    req.session.current_user_email = email;
    req.session.user = { email, first_name, last_name };
    req.session.account_id = row.account_id;

    return req.session.save((err) => {
      if (err) {
        return res.status(500).json({ success: false, message: 'Session error' });
      }

      logger.info('[api] Response', {
        path: '/api/auth/register',
        success: true,
        user_id: row.user_id,
        account_id: row.account_id
      });
      return res.json({ success: true, redirectTo: '/wf-dashboard' });
    });
  } catch (err) {
    logger.error('[api] Response', {
      path: '/api/auth/register',
      success: false,
      error: err.message
    });
    return res.status(500).json({ success: false, message: 'Registration service unavailable' });
  }
}
