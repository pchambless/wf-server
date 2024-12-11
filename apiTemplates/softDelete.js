require('module-alias/register');
const { executeQuery } = require('@utils/dbUtils');
const { sendResponse, handleError } = require('@utils/responseUtils');

module.exports = async (req, res) => {
  const codeName = '[{{eventType}}.js]';
  const params = req.body; // Access params object directly
  const { userId } = req.user; // Assuming user ID is stored in req.user

  console.log(`${codeName} Received request with: ${JSON.stringify(req.body)}`);

  // Ensure the required params are present
  const requiredParam = '{{params}}'.replace(/[{}]/g, '');
  if (!params[requiredParam]) {
    return handleError(res, codeName, `${requiredParam} is required`, 400);
  }

  const query = `{{qrySQL}}`;

  try {
    const data = await executeQuery(query, [userId, params[requiredParam]], [], res, codeName);
    sendResponse(res, data, codeName);
  } catch (error) {
    handleError(res, codeName, `Error soft deleting record: ${error.message}`, 500);
  }
};
