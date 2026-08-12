import { Router } from 'express';
import { handleLogin } from '../controllers/loginHandler.js';
import { handleRegister } from '../controllers/registerHandler.js';
import { handleChangePassword } from '../controllers/changePasswordHandler.js';
import { handleAdminResetPassword } from '../controllers/adminResetPasswordHandler.js';
import hydrateRoutes from './hydrateRoutes.js';
import actionRoutes from './actionRoutes.js';
import dmlRoutes from './dmlRoutes.js';
import batchMapRoutes from './batchMapRoutes.js';

const router = Router();

router.post('/auth/login', handleLogin);
router.post('/auth/register', handleRegister);
router.post('/auth/change-password', handleChangePassword);
router.post('/admin/reset-password', handleAdminResetPassword);
router.use(hydrateRoutes);
router.use(actionRoutes);
router.use(dmlRoutes);
router.use(batchMapRoutes);

export default router;
