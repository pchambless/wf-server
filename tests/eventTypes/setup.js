const { eventTypeCache, cacheEventTypes, closePool } = require('../../config/cache');

beforeAll(async () => {
  let cachedEvents = eventTypeCache.get('eventTypes');

  if (!cachedEvents || cachedEvents.length === 0) {
    console.log('Loading event types:');
    await cacheEventTypes(); // Reload the cache if it's empty
    await new Promise((resolve) => setTimeout(resolve, 1000)); // Ensure the cache is fully loaded
    cachedEvents = eventTypeCache.get('eventTypes');
    console.log('Cache reloaded. Cached events:', cachedEvents);
  } else {
    console.log('Event types already cached:', cachedEvents);
  }
});

afterAll(async () => {
  await closePool(); // Ensure the pool is closed
  const { closeServer } = require('../../jestUtils'); // Adjust the path as needed
  await closeServer();
});
