require('module-alias/register');
const fs = require('fs');
const path = require('path');
const codeName = `[fetchEventTypes.js] `;

const genEventTypeFile = async (connection) => {
  try {
    const [rows] = await connection.execute('SELECT * ' +
                                            ' FROM api_wf.apiEventList');
    console.log(codeName + '.genEventTypeFile: EventType count loaded from database:', rows.length);

    const eventTypesPath = path.join(__dirname, '../middleware/eventTypes.js');
    const eventTypesContent = `module.exports = ${JSON.stringify(rows, null, 2)};`;

    fs.writeFileSync(eventTypesPath, eventTypesContent);
    console.log(codeName,'.genEventTypeFile: eventTypes.js file generated.');

    return rows;
  } catch (error) {
    console.error(codeName + '.genEventTypeFile: Error generating eventTypes.js:', error.message );
  }
};

const fetchEventTypes = (req, res) => {
  try {
    const eventTypesPath = path.resolve(__dirname, '../middleware/eventTypes.js');
    const eventTypes = require(eventTypesPath);

    res.status(200).json({
      message: 'Event types retrieved successfully', 
      eventTypes: eventTypes
    });
  } catch (error) { 
    console.error('Error fetching event types:', error);  
    res.status(500).send('Internal server error'); 
  }
};

module.exports = { genEventTypeFile, fetchEventTypes };
