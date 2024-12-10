// server/middleware/eventLookup.js
const eventRoutes = require('./eventRoutes');

const eventLookup = (eventType) => {
  console.log(`[eventLookup] Received eventType: ${eventType}`);

  const eventRoute = eventRoutes.find(route => route.eventType === eventType);

  if (!eventRoute) {
    throw new Error(`No route found for eventType: ${eventType}`);
  }

  console.log(`[eventLookup] Event config for type ${eventType}: ${JSON.stringify(eventRoute)}`);

  const { method, path } = eventRoute;

  return {
    method,
    path
  };
};

module.exports = eventLookup;
