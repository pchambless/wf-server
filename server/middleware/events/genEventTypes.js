const fs = require('fs');
const path = require('path');

const genEventTypeFile = async (connection) => {
  try {
    const [rows] = await connection.execute('SELECT eventType, method, path, params, bodyCols, qrySQL, parent ' +
                                            ' FROM v_apiEventsLoad ' +
                                            ' ORDER BY path');
    console.log('[genEventTypes.js] Loaded event types from database:', rows);

    const eventRoutesPath = path.join(__dirname, '../events/eventRoutes.js');
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
  } catch (error) {
    console.error('[genEventTypes.js] Error generating eventRoutes.js:', error.message);
  }
};

module.exports = { genEventTypeFile };
