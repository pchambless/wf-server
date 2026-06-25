import { Router } from 'express';
import { handleLogin } from '../controllers/loginHandler.js';
import hydrateRoutes from './hydrateRoutes.js';
import actionRoutes from './actionRoutes.js';
import dmlRoutes from './dmlRoutes.js';
import batchMapRoutes from './batchMapRoutes.js';

const router = Router();

router.post('/auth/login', handleLogin);
router.use(hydrateRoutes);
router.use(actionRoutes);
router.use(dmlRoutes);
router.use(batchMapRoutes);

export default router;
