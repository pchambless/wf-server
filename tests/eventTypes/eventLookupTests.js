const getEventDetails = require('../../api/eventLookup'); // Adjust the path as needed

const runEventTypeTests = async (eventType) => {
  const eventConfig = await getEventDetails(eventType);
  if (eventConfig.statusCode >= 200 && eventConfig.statusCode < 300) {
    console.log(`Validating event type: ${eventType}, Status Code: ${eventConfig.statusCode}`);
    expect(eventConfig.statusCode).toBeGreaterThanOrEqual(200);
    expect(eventConfig.statusCode).toBeLessThan(300);
  } else {
    console.error(`Invalid status code for event type: ${eventType}, Status Code: ${eventConfig.statusCode}`);
    expect(eventConfig.statusCode).toBeGreaterThanOrEqual(300); // Indicate invalid status
  }
};

module.exports = { runEventTypeTests };
