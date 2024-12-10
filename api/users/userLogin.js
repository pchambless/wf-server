const { executeQuery } = require('@utils/dbUtils');
const { sendResponse, handleError } = require('@utils/responseUtils');

module.exports = async (req, res) => {
  const codeName = '[userLogin.js]';
  const body = req.body;
  console.log(`${codeName} Received request with: ${JSON.stringify(body)}`);

  // Build the values dynamically from the request body
  const values = Object.values(body);

  // Ensure all required fields are present
  const missingFields = Object.keys(body).filter(key => !body[key]);
  if (missingFields.length) {
    return handleError(res, codeName, `Missing fields: ${missingFields.join(', ')}`, 400);
  }

  const query = `select id
from users
where email = ?
and password = ?`;

  try {
    const data = await executeQuery(query, values, [], res, codeName);
    sendResponse(res, data, codeName);
  } catch (error) {
    handleError(res, codeName, `Error creating record: ${error.message}`, 500);
  }
};
