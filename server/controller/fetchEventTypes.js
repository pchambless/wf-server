require('module-alias/register');
const fs = require('fs').promises;
const path = require('path');
const logger = require('@utils/logger');
const codeName = '[fetchEventTypes.js]';

async function genEventTypeFile(connection) {
  try {
    const [rows] = await connection.execute('SELECT * FROM api_wf.apiEventList');
    logger.info(`${codeName} Event types loaded from database`, { count: rows.length });

    const eventTypesPath = path.join(__dirname, '../middleware/eventTypes.js');
    const fileContent = `module.exports = ${JSON.stringify(rows, null, 2)};`;
    
    await fs.writeFile(eventTypesPath, fileContent, 'utf8');
    logger.info(`${codeName} eventTypes.js file generated successfully`);
    
    return rows;
  } catch (error) {
    logger.error(`${codeName} Error generating eventTypes.js:`, error);
    throw error;
  }
}

async function fetchEventTypes(req, res) {
  try {
    const connection = global.pool;
    const eventTypes = await genEventTypeFile(connection);
    
    logger.debug(`${codeName} Fetched event types`, { count: eventTypes.length });
    res.json({
      success: true,
      data: eventTypes
    });
  } catch (error) {
    logger.error(`${codeName} Error fetching event types:`, error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch event types',
      error: error.message
    });
  }
}

module.exports = {
  genEventTypeFile,
  fetchEventTypes
};
