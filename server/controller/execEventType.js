require('module-alias/register');
const { createRequestBody } = require('@utils/queryResolver'); // Import createRequestBody function
const { executeQuery } = require('@utils/dbUtils');
const logger = require('@utils/logger');
const codeName = `[execEventType.js]`;

// Load eventTypes directly from the file
const eventTypes = require('@middleware/eventTypes');

module.exports = async (req, res) => {
  logger.http(`${codeName} Request received`, {
    method: req.method,
    originalUrl: req.originalUrl,
    headers: req.headers,
    body: req.body
  });

  const { eventType, params } = req.body; 

  // Log the received parameters
  logger.debug(`${codeName} Parameters:`, params);

  try {
    // Find the eventType directly from the loaded eventTypes
    const eventRoute = eventTypes.find(event => event.eventType === eventType);
    if (!eventRoute) {
      logger.warn(`${codeName} Invalid eventType: ${eventType}`);
      return res.status(400).json({
        error: 'Invalid eventType',
        message: `Event type '${eventType}' not found`
      });
    }

    const { qrySQL, method } = eventRoute;
    logger.debug(`${codeName} Executing query with event type method: ${method}`);

    // Use queryResolver to handle parameter substitution
    const qryMod = createRequestBody(qrySQL, params);
    logger.debug(`${codeName} Modified query:`, qryMod);

    // Execute the modified query
    const result = await executeQuery(qryMod, method);
    logger.info(`${codeName} Query executed successfully for ${eventType}`);
    res.json(result);

  } catch (error) {
    logger.error(`${codeName} Error executing event type:`, error);
    res.status(500).json({
      error: 'Internal Server Error',
      message: error.message
    });
  }
};
