require('module-alias/register');
const eventRoutes = require('@middleware/events/eventRoutes');
const db = require('@utils/dbUtils');
const codeName = '[mapEventController] ';

module.exports = async (req, res) => {
  const { eventType, queryParams, body } = req.body;

  const eventRoute = eventRoutes.find(route => route.eventType === eventType);
  if (!eventRoute) {
    return res.status(400).send('Invalid eventType');
  }

  const { method, qrySQL } = eventRoute;

  try {
    const params = method === 'GET' ? queryParams : body;
    const result = await db.executeQuery(qrySQL, params);
    console.log(codeName,`eventType -> '`,eventType,`': Successful`)
    res.status(200).json(result);
  } catch (error) {
    console.error(codeName + `eventType -> ` + eventType + 'Failed:', error);
    res.status(500).send('Internal server error');
  }
};
