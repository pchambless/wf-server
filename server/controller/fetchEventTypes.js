require('module-alias/register');
const fs = require('fs');
const path = require('path');
const codeName = `[fetchEventTypes.js] `;

const genEventTypeFile = async (connection) => {
  try {
    const [rows] = await connection.execute('SELECT * ' +
                                            ' FROM v_apiEventsLoad ' +
                                            ' ORDER BY path, eventType');
    console.log(codeName + '.genEventTypeFile: EventType count loaded from database:', rows.length);

    const eventRoutesPath = path.join(__dirname, '../middleware/eventRoutes.js');
    const eventRoutesContent = `module.exports = ${JSON.stringify(rows, null, 2)};`;

    fs.writeFileSync(eventRoutesPath, eventRoutesContent);
    console.log(codeName,'.genEventTypeFile: eventRoutes.js file generated.');

    return rows;
  } catch (error) {
    console.error(codeName + '.genEventTypeFile: Error generating eventRoutes.js:', error.message);
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
