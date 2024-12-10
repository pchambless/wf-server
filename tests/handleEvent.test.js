const axios = require('axios');

describe('handleEvent Endpoint', () => {
  const validEventTypes = [
    { eventType: 'ingrTypeList', params: { acctID: 1 } },
    { eventType: 'userAccts', params: { userID: 123 } },
    { eventType: 'userLogin', params: { userEmail: 'test@example.com', password: 'password123' } },
    { eventType: 'bogusEvent', params: { bogusID: 1 } },
  ];

  validEventTypes.forEach(event => {
    it(`should handle ${event.eventType} event type correctly`, async () => {
      const response = await axios.post('http://localhost:3001/api/handleEvent', event);
      console.log(`Status: ${response.status}, EventType: ${event.eventType}, Method: ${response.config.method}, Path: ${response.config.url}, Params:`, event.params);

      expect(response.status).toBe(200);
      expect(response.data).toEqual({ success: true }); // Adjust based on your actual response
    });
  });

  it('should return error if event type is missing', async () => {
    try {
      const response = await axios.post('http://localhost:3001/api/handleEvent', { params: { userEmail: 'test@example.com', password: 'password123' } });
      console.log(`Status: ${response.status}, EventType: undefined, Method: ${response.config.method}, Path: ${response.config.url}, Params: { userEmail: 'test@example.com', password: 'password123' }`);
    } catch (error) {
      console.log(`Status: ${error.response.status}, EventType: undefined, Method: N/A, Path: N/A, Params: { userEmail: 'test@example.com', password: 'password123' }`);
      expect(error.response.status).toBe(400);
      expect(error.response.data).toEqual({ error: 'Event type is required' });
    }
  });
});
