import { Router } from 'express';
import verifyPassword from '../controllers/authVerify.js';
import { renderPage } from '../renderers/pageRenderer.js';

const router = Router();

router.post('/auth/verify', verifyPassword);

router.get('/page/*', renderPage);

export default router;
