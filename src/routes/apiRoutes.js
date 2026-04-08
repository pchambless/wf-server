import { Router } from 'express';
import verifyPassword from '../controllers/authVerify.js';

const router = Router();

router.post('/auth/verify', verifyPassword);

export default router;
