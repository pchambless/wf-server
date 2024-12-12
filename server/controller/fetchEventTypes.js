require('module-alias/register');
const fs = require('fs');
const path = require('path');

const genEventTypeFile = async (connection) => {
  try {
    const [rows] = await connection.execute('SELECT eventType, method, path, params, bodyCols, qrySQL, parent ' +
                                            ' FROM v_apiEventsLoad ' +
                                            ' ORDER BY path');
    console.log('[genEventTypes.js] Loaded event types from database:', rows);

    const eventRoutesPath = path.join(__dirname, '../middleware/events/eventRoutes.js');
    console.log('[genEventTypes.js] eventRoutesPath:', eventRoutesPath);

    // Ensure the directory exists
    const dir = path.dirname(eventRoutesPath);
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
      console.log('[genEventTypes.js] Directory created:', dir);
    }

    const eventRoutesContent = `module.exports = ${JSON.stringify(rows, null, 2)};`;
    console.log('[genEventTypes.js] Writing to eventRoutes.js with content:', eventRoutesContent);

    fs.writeFileSync(eventRoutesPath, eventRoutesContent);
    console.log('[genEventTypes.js] server/middleware/events/eventRoutes.js file generated.');

    return rows;
  } catch (error) {
    console.error('[genEventTypes.js] Error generating eventRoutes.js:', error.message);
  }
};

const fetchEventTypes = (req, res) => {
  try {
    const eventRoutesPath = path.resolve(__dirname, '../middleware/events/eventRoutes.js');
    const eventRoutes = require(eventRoutesPath);

    res.status(200).json({
      message: 'Event types retrieved successfully',
      eventTypes: eventRoutes
    });
  } catch (error) {
    console.error('Error fetching event types:', error);
    res.status(500).send('Internal server error');
  }
};

module.exports = { genEventTypeFile, fetchEventTypes };
