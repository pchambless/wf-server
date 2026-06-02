import { Router } from 'express';
import { handleLogin } from '../controllers/loginHandler.js';
import hydrateRoutes from './hydrateRoutes.js';
import actionRoutes from './actionRoutes.js';

const router = Router();

router.post('/auth/login', handleLogin);
router.use(hydrateRoutes);
router.use(actionRoutes);

export default router;
