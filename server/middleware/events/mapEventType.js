// server/middleware/mapEventType.js
const eventLookup = require('./eventLookup');
const path = require('path');

const MAX_RECURSIVE_CALLS = 1;

const mapEventType = async (req, res) => {
  const { eventType, queryParams = {}, body = {} } = req.body;
  const counter = parseInt(req.headers['x-counter'] || 0, 10);
  console.log(`[mapEventType] Received request for eventType: ${eventType} with counter: ${counter}`);
  console.log(`[mapEventType] Query Params: ${JSON.stringify(queryParams)}`);
  console.log(`[mapEventType] Body: ${JSON.stringify(body)}`);

  if (counter >= MAX_RECURSIVE_CALLS) {
    console.log(`[mapEventType] Exceeded max recursive calls: ${counter}`);
    return res.status(400).json({ success: false, message: 'Exceeded maximum recursive calls' });
  }

  try {
    const eventConfig = eventLookup(eventType);
    console.log(`[mapEventType] Resolved endpoint with method=${eventConfig.method}, path=${eventConfig.path}`);

    // Ensure the path is correctly resolved relative to the project root
    const handlerPath = path.resolve(__dirname, '..', '..', `.${eventConfig.path}`);
    console.log(`[mapEventType] Attempting to load handler from path: ${handlerPath}`);

    const handler = require(handlerPath);
    console.log(`[mapEventType] Successfully loaded handler from path: ${handlerPath}`);
    
    req.query = queryParams;
    req.body = body;

    return handler(req, res);
  } catch (error) {
    console.error(`[mapEventType] Error: ${error.message}`);
    res.status(500).json({ success: false, message: 'Internal Server Error' });
  }
};

module.exports = mapEventType;
