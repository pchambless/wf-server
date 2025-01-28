require('module-alias/register');
const fs = require('fs');
const path = require('path');
const { executeQuery } = require('@utils/dbUtils'); // Assuming executeQuery is a function to run SQL queries
const codeName = `[fetchApiColumns.js.js] `;

// Function to generate apiColumns file by running a direct SQL query
const genApiColumnFile = async (connection) => {
  try {
    const [rows] = await connection.execute('SELECT * FROM api_wf.apiColumns');
    console.log(codeName + '.genApiColumnFile: apiColumns count loaded from database:', rows.length);

    const apiColumnsPath = path.join(__dirname, '../middleware/apiColumns.js');
    const apiColumnsContent = `module.exports = ${JSON.stringify(rows, null, 2)};`;

    fs.writeFileSync(apiColumnsPath, apiColumnsContent);
    console.log(codeName + '.genApiColumnFile: apiColumns.js file generated.');

    return rows;
  } catch (error) {
    console.error(codeName + '.genApiColumnFile: Error generating apiColumns.js:', error.message);
  }
};

// Function to fetch apiColumns from the file
const fetchApiColumns = async (req, res) => {
  try {
    const apiColumnsPath = path.resolve(__dirname, '../middleware/apiColumns.js');
    const apiColumns = require(apiColumnsPath);

    res.status(200).json({
      message: 'apiColumns retrieved successfully',
      apiColumns: apiColumns
    });
  } catch (error) {
    console.error(codeName + 'Error fetching apiColumns:', error);
    res.status(500).send('Internal server error');
  }
};

module.exports = { genApiColumnFile, fetchApiColumns };
