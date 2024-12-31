require('module-alias/register');
const { createRequestBody } = require('@utils/queryResolver'); // Import createRequestBody function
const eventRoutes = require('@middleware/eventRoutes');
const { executeQuery } = require('@utils/dbUtils');
const codeName = `[execEventType.js] `;

module.exports = async (req, res) => {
  console.log(codeName, '[Request]', {
    method: req.method,
    originalUrl: req.originalUrl,
    headers: req.headers,
    body: JSON.stringify(req.body, null, 2) // Ensure nested objects are correctly logged
  });

  const { eventType, params } = req.body;

  const eventRoute = eventRoutes.find(route => route.eventType === eventType);
  if (!eventRoute) {
    console.error(codeName, `Invalid eventType: ${eventType}`);
    return res.status(400).send('Invalid eventType');
  }

  const { qrySQL, method } = eventRoute; // Retrieve the method from eventRoute

  const requestBody = createRequestBody(qrySQL, params);

  console.log(codeName, '[Request Body]', JSON.stringify(requestBody, null, 2));

  try {
    const result = await executeQuery(requestBody.qryMod, method); // Pass method along with qryMod and params
    console.log(codeName, `eventType -> '${eventType}' [${method}]: Successful`, JSON.stringify(result, null, 2));
    res.status(200).json(result);
  } catch (error) {
    console.error(codeName, `eventType -> ${eventType} Failed:`, error);
  
    // Send detailed error response
    const errorDetails = {
      message: 'Internal server error',
      error: error.message,
      stack: error.stack,
      type: 'execution_error'
    };
    res.status(500).json(errorDetails);
  }  
};
