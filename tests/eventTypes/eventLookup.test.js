require('./setup'); // Ensure the setup is run before tests
const { runEventTypeTests } = require('./eventLookupTests');
const { eventTypeCache, cacheEventTypes } = require('../../config/cache');

describe('getEventDetails Function', () => {
  let cachedEvents = [];

  beforeAll(async () => {
    cachedEvents = eventTypeCache.get('eventTypes');
    if (!cachedEvents || cachedEvents.length === 0) {
      console.log('Cache is empty, reloading...');
      await cacheEventTypes(); // Reload the cache if it's empty
      await new Promise((resolve) => setTimeout(resolve, 1000)); // Ensure the cache is fully loaded
      cachedEvents = eventTypeCache.get('eventTypes');
      console.log(`Cache reloaded. Event Type count: ${cachedEvents.length}`);
    } else {
      console.log(`Cached event count in beforeAll: ${cachedEvents.length}`);
    }
  });

  it('should have loaded events in the cache', () => {
    cachedEvents = eventTypeCache.get('eventTypes');
    console.log(`Event Type count for testing: ${cachedEvents.length}`);
    expect(cachedEvents).toBeDefined();
    expect(cachedEvents.length).toBeGreaterThan(0);
  });

  // Define tests for each event type synchronously after cache is loaded
  afterAll(async () => {
    for (const event of cachedEvents) {
      it(`should validate the path and status code for event type ${event.eventType}`, async () => {
        console.log(`Running test for event: ${event.eventType}`);
        await runEventTypeTests(event.eventType);
      });
    }
  });
});
