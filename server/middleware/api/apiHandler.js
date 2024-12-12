// server/middleware/apiHandler.js
require('module-alias/register');
const axios = require('axios');
const eventLookup = require('@events/eventLookup');

const MAX_RECURSIVE_CALLS = 1;

const apiHandler = async (req, res, eventType, queryParams, body) => {
  const counter = parseInt(req.headers['x-counter'] || 0, 10);
  console.log(`[apiHandler] Received request for eventType: ${eventType} with counter: ${counter}`);

  if (counter >= MAX_RECURSIVE_CALLS) {
    console.log(`[apiHandler] Exceeded max recursive calls: ${counter}`);
    return res.status(400).json({ success: false, message: 'Exceeded maximum recursive calls' });
  }

  try {
    const eventConfig = await eventLookup(eventType, queryParams, body);
    const { method, url, params, data } = eventConfig;
    console.log(`[apiHandler] Resolved endpoint with method=${method}, url=${url}, params=${JSON.stringify(params)}, data=${JSON.stringify(data)}`);

    // Make the external API call using a separate function to avoid recursion
    await makeApiCall(res, method, url, params, data, counter);
  } catch (error) {
    console.error(`[apiHandler] Error in eventLookup: ${error.message}`);
    res.status(500).json({ success: false, message: 'Internal Server Error' });
  }
};

const makeApiCall = async (res, method, url, params, data, counter) => {
  try {
    const response = await axios({
      method,
      url: `http://localhost:3001${url}`,
      params,
      data,
      headers: { 'x-counter': counter + 1 }
    });

    console.log(`[makeApiCall] API response received: ${JSON.stringify(response.data)}`);
    res.json(response.data);
  } catch (error) {
    console.error(`[makeApiCall] Error in API call: ${error.message}`);
    res.status(500).json({ success: false, message: 'Internal Server Error' });
  }
};

module.exports = apiHandler;
