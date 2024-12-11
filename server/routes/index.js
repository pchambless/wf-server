require('module-alias/register');
const express = require('express');
const router = express.Router();
const path = require('path');
const eventRoutes = require('@middleware/events/eventRoutes');
const { executeQuery, sendResponse, handleError } = require('@utils/dbUtils');
const mapEventTypeController = require('@controller/mapEventType');
const initializeController = require('@controller/initializeController');

const determineMethod = (method) => {
  switch (method.toUpperCase()) {
    case 'GET':
      return 'get';
    case 'POST':
      return 'post';
    case 'PATCH':
      return 'patch';
    case 'SDELETE':
      return 'patch'; // Map SDELETE to PATCH method
    default:
      return 'get'; // Default to GET
  }
};

// Register each route dynamically with its metadata
eventRoutes.forEach((route) => {
  const { eventType, method, path: routePath, qrySQL, params, bodyCols } = route;
  const codeName = `[${eventType}.js]`;

  router[determineMethod(method)](routePath, async (req, res) => {
    const queryParams = req.query;
    const body = req.body;

    console.log(`${codeName} Received request with: ${JSON.stringify(req.query)} and body: ${JSON.stringify(req.body)}`);
    console.log(`${codeName} Params: ${params}, qrySQL: ${qrySQL}, bodyCols: ${bodyCols}`);

    // Ensure all expected query parameters are present
    const requiredParams = params ? params.split(',') : [];
    const missingParams = requiredParams.filter(param => !queryParams[param]);
    if (missingParams.length) {
      console.error(`${codeName} Missing query parameters: ${missingParams.join(', ')}`);
      return res.status(400).json({ success: false, message: `Missing query parameters: ${missingParams.join(', ')}` });
    }

    // Ensure all expected body columns are present if applicable
    if (bodyCols) {
      const requiredBodyCols = bodyCols.split(',');
      const missingBodyCols = requiredBodyCols.filter(col => !body[col]);
      if (missingBodyCols.length) {
        console.error(`${codeName} Missing body columns: ${missingBodyCols.join(', ')}`);
        return res.status(400).json({ success: false, message: `Missing body columns: ${missingBodyCols.join(', ')}` });
      }
    }

    try {
      const queryValues = requiredParams.map(param => queryParams[param]);
      console.log(`${codeName} Executing query: ${qrySQL} with params: ${JSON.stringify(queryValues)}`);
      const data = await executeQuery(qrySQL, queryValues, [], res, codeName);
      console.log(`${codeName} Query executed successfully, data: ${JSON.stringify(data)}`);
      return res.status(200).json({ success: true, data });
    } catch (error) {
      console.error(`${codeName} Error retrieving data: ${error.message}`);
      return res.status(500).json({ success: false, message: `Error retrieving data: ${error.message}` });
    }
  });

  console.log(`[REGISTER] ${method.toUpperCase()} ${routePath}`);
});

// Add the mapEventType route
router.post('/api/mapEventType', mapEventTypeController);

// Add the initialize route
router.post('/api/initialize', initializeController.initialize);

// Function to initialize routes
const initializeRoutes = (app) => {
  app.use('/', router);
};

module.exports = { initializeRoutes };
