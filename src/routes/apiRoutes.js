import express from 'express';
import verifyPassword from '../controllers/authVerify.js';

const router = express.Router();

// Auth endpoints
router.post('/auth/verify', verifyPassword);

export default router;
