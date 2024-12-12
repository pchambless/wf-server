require('module-alias/register');
const eventRoutes = require('@middleware/events/eventRoutes');
const db = require('@utils/dbUtils');

module.exports = async (req, res) => {
  const { eventType, queryParams, body } = req.body;

  // Find the route definition based on eventType
  const eventRoute = eventRoutes.find(route => route.eventType === eventType);
  if (!eventRoute) {
    return res.status(400).send('Invalid eventType');
  }

  // Extract necessary information from the route definition
  const { method, qrySQL } = eventRoute;

  try {
    let result;
    // Handle different HTTP methods
    switch (method) {
      case 'GET':
        const params = Object.values(queryParams);
        result = await db.executeQuery(qrySQL, params);
        break;
      case 'POST':
      case 'PATCH':
      case 'DELETE':
        const bodyValues = Object.values(body);
        result = await db.executeQuery(qrySQL, bodyValues);
        break;
      default:
        return res.status(400).send('Unsupported HTTP method');
    }
    res.status(200).json(result);
  } catch (error) {
    console.error('Error processing event:', error);
    res.status(500).send('Internal server error');
  }
};
