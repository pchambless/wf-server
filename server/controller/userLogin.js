const bcrypt = require('bcrypt');
const { createRequestBody } = require('@utils/queryResolver'); // Import createRequestBody function
const { executeQuery } = require('@utils/dbUtils');
const logger = require('@utils/logger');
const codeName = '[userLogin.js]';

// Clear require cache
Object.keys(require.cache).forEach(function(key) {
    delete require.cache[key];
});

// Load eventTypes directly from the file
const eventTypes = require('@middleware/eventTypes');

async function rehashPassword(userEmail, oldHash) {
    try {
        const newHash = await bcrypt.hash(oldHash, 10);
        logger.debug(`${codeName} Password rehash generated`, { userEmail });

        const updateQuery = 'UPDATE api_wf.userList SET password = ? WHERE userEmail = ?';
        await executeQuery(updateQuery, 'PATCH', [newHash, userEmail]);
        logger.info(`${codeName} Password rehashed and updated`, { userEmail });
    } catch (error) {
        logger.error(`${codeName} Error rehashing password:`, error);
        throw error;
    }
}

async function login(req, res) {
    logger.info(`${codeName} Login attempt started`);
    
    try {
        const { userEmail, password } = req.body;

        if (!userEmail || !password) {
            logger.warn(`${codeName} Missing credentials`, { userEmail: !!userEmail, password: !!password });
            return res.status(400).json({
                success: false,
                message: 'Email and password are required'
            });
        }

        logger.debug(`${codeName} Executing user lookup query`, { userEmail });

        // Find the eventType for userLogin directly from the loaded eventTypes
        const eventRoute = eventTypes.find(event => event.eventType === 'userLogin');
        if (!eventRoute) {
            logger.warn(`${codeName} Invalid eventType: userLogin`);
            return res.status(400).json({
                success: false,
                message: 'Invalid eventType'
            });
        }

        const { qrySQL, method } = eventRoute;
        const params = { ":userEmail": userEmail, ":enteredPassword": password };
        const qryMod = createRequestBody(qrySQL, params);
        logger.debug(`${codeName} Modified query: ${qryMod}`);
        
        // Add logging before executing the query
        logger.debug(`${codeName} About to execute query`, { qryMod, method });
        const users = await executeQuery(qryMod, method);
        logger.debug(`${codeName} Query executed`, { users });

        if (users.length === 0) {
            logger.warn(`${codeName} User not found`, { userEmail });
            return res.status(401).json({
                success: false,
                message: 'Invalid email or password'
            });
        }

        const user = users[0];
        const passwordMatch = await bcrypt.compare(password, user.password);
        
        logger.debug(`${codeName} Password verification result`, { 
            userEmail,
            matched: passwordMatch,
            needsRehash: passwordMatch && user.password.length < 60
        });

        if (!passwordMatch) {
            logger.warn(`${codeName} Invalid password attempt`, { userEmail });
            return res.status(401).json({
                success: false,
                message: 'Invalid email or password'
            });
        }

        // If using an old hash format, rehash the password
        if (user.password.length < 60) {
            await rehashPassword(userEmail, user.password);
        }

        const response = {
            success: true,
            user: {
                id: user.userID,
                email: user.userEmail,
                name: `${user.firstName} ${user.lastName}`,
                role: user.roleID
            }
        };

        logger.info(`${codeName} Login successful`, { userEmail });
        res.json(response);

    } catch (error) {
        logger.error(`${codeName} Login error:`, error);
        res.status(500).json({
            success: false,
            message: 'Internal server error'
        });
    }
}

module.exports = login;
