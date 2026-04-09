import { callWorkflow } from '../utils/n8nClient.js';

export async function handleLogin(req, res) {
  const { email, password } = req.body;

  if (!email || !password) {
    return res.status(400).json({ success: false, message: 'Email and password required' });
  }

  try {
    const result = await callWorkflow('login', { email, password });

    if (result?.success) {
      req.session.current_user_email = email;
      req.session.user = result.user || { email };

      return req.session.save((err) => {
        if (err) {
          return res.status(500).json({ success: false, message: 'Session error' });
        }
        return res.json({ success: true, redirectTo: '/whatsfresh/wf-dashboard' });
      });
    }

    return res.status(401).json({ success: false, message: result?.message || 'Invalid email or password' });
  } catch (err) {
    return res.status(500).json({ success: false, message: 'Login service unavailable' });
  }
}
