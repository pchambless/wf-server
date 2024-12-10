// server/middleware/callAPI.js
const axios = require('axios');

const callAPI = async (method, url, params, data, counter) => {
  try {
    const response = await axios({
      method,
      url: `http://localhost:3001${url}`,
      params,
      data,
      headers: { 'x-counter': counter + 1 }
    });

    console.log(`[callAPI] API response received: ${JSON.stringify(response.data)}`);
    return response.data;
  } catch (error) {
    throw new Error(`[callAPI] Error in API call: ${error.message}`);
  }
};

module.exports = callAPI;
