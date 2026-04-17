import { Router } from 'express';
import { handleLogin } from '../controllers/loginHandler.js';
import { callWorkflow } from '../utils/n8nClient.js';

const router = Router();

router.post('/auth/login', handleLogin);

router.post('/hydrate', async (req, res) => {
  const { template_name } = req.body;
  const result = await callWorkflow('hydrate-guide', {
    template_name, source: 'wf-server', format: 'html'
  });
  const html = typeof result === 'string' ? result : result?.html || result?.[0]?.html || '';
  res.type('html').send(html);
});

export default router;
