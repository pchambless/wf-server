require('module-alias/register');
const { executeQuery } = require('@utils/dbUtils');
const { sendResponse, handleError } = require('@utils/responseUtils');

module.exports = async (req, res) => {
  const codeName = '[{{eventType}}.js]';
  const body = req.body;
  const params = req.params; // Access params object directly

  console.log(`${codeName} Received request with: ${JSON.stringify(body)}`);

  // Ensure the required params are present
  const requiredParam = '{{params}}'.replace(/[{}]/g, '');
  if (!params[requiredParam]) {
    return handleError(res, codeName, `${requiredParam} is required`, 400);
  }

  // Build dynamic columns and values for the SQL query
  const columns = Object.keys(body).map(key => `${key} = ?`).join(', ');
  const values = Object.values(body);
  values.push(params[requiredParam]); // Add the primary key value to the end of the values array

  const query = `UPDATE {{tableName}} SET ${columns} WHERE ${requiredParam} = ?`;

  try {
    const data = await executeQuery(query, values, [], res, codeName);
    sendResponse(res, data, codeName);
  } catch (error) {
    handleError(res, codeName, `Error updating record: ${error.message}`, 500);
  }
};
