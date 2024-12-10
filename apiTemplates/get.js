const { executeQuery } = require('@utils/dbUtils');
const { sendResponse, handleError } = require('@utils/responseUtils');

module.exports = async (req, res) => {
  const codeName = '[{{eventType}}.js]';
  const queryParams = req.query; // Access query parameters directly

  console.log(`${codeName} Received request with: ${JSON.stringify(req.query)}`);

  // Ensure all expected query parameters are present
  const requiredParams = ['acctID']; // Adjust as needed based on your requirements
  const missingParams = requiredParams.filter(param => !queryParams[param]);
  if (missingParams.length) {
    return handleError(res, codeName, `Missing query parameters: ${missingParams.join(', ')}`, 400);
  }

  const query = `{{qrySQL}}`;

  try {
    const data = await executeQuery(query, [queryParams.acctID], [], res, codeName);
    sendResponse(res, data, codeName);
  } catch (error) {
    handleError(res, codeName, `Error retrieving data: ${error.message}`, 500);
  }
};