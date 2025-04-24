require('module-alias/register');
const eventTypes = require('@middleware/eventTypes');
const dbUtils = require('@utils/dbUtils');
const codeName = '[queryResolver.js]';

module.exports = async (req, res) => {
  // Log the incoming request
  console.log(codeName, '[Request]', {
    method: req.method,
    originalUrl: req.originalUrl,
    headers: req.headers,
    body: req.body
  });

  const { eventType, queryParams } = req.body;

  const eventRoute = eventTypes.find(route => route.eventType === eventType);
  if (!eventRoute) {
    console.error(codeName, `Invalid eventType: ${eventType}`);
    return res.status(400).send('Invalid eventType');
  }

  const { qrySQL } = eventRoute;

  try {
    const params = queryParams;

    // Use dbUtils to replace named parameters and get the resolved query
    const resolvedQuery = dbUtils.replaceNamedParams(qrySQL, params);

    // Return the resolved query
    res.status(200).json({ resolvedQuery });
  } catch (error) {
    console.error(codeName, `Failed to resolve query:`, error);
    res.status(500).send('Internal server error');
  }
};
