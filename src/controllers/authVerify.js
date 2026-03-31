import bcrypt from 'bcrypt';
import { callWorkflow } from '../utils/n8nClient.js';
import logger from '../utils/logger.js';

const codeName = '[authVerify.js]';

async function verifyPassword(req, res) {
    try {
        const { email, password } = req.body;

        logger.debug(`${codeName} Verify request for:`, { email });

        if (!email || !password) {
            return res.status(400).json({
                passwordMatches: false,
                error: 'Email and password required'
            });
        }

        // Get user + hash from n8n
        const users = await callWorkflow('hydrate-guide', {
            function: 'whatsfresh.api_login',
            params: { p_email: email },
            source: 'server',
            format: 'json',
            type: 'json'
        });

        const user = Array.isArray(users) ? users[0] : users?.data?.[0];

        if (!user || !user.password) {
            logger.warn(`${codeName} User not found:`, { email });
            return res.status(401).json({ passwordMatches: false });
        }

        // Verify bcrypt
        const matches = await bcrypt.compare(password, user.password);

        logger.debug(`${codeName} Password verification:`, { email, matches });

        if (matches) {
            return res.status(200).json({
                passwordMatches: true,
                user_id: user.user_id,
                email: user.email,
                first_name: user.first_name,
                last_name: user.last_name,
                role_id: user.role_id,
                default_account_id: user.default_account_id
            });
        } else {
            return res.status(401).json({ passwordMatches: false });
        }

    } catch (error) {
        logger.error(`${codeName} Error:`, error);
        res.status(500).json({ passwordMatches: false, error: 'Internal error' });
    }
}

export default verifyPassword;
