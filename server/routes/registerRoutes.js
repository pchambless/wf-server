require('module-alias/register');
const express = require('express');
const execEventType = require('@controller/execEventType');
const initializeController = require('@controller/initialize');
const listRoutesController = require('@controller/listRegisteredRoutes');
const restartServerController = require('@controller/restartServer');
const { fetchEventTypes } = require('@controller/fetchEventTypes');
const { fetchApiColumns } = require('@controller/apiColumnsController'); 
const codeName = `[registerRoutes.js] `;

module.exports = (app) => {
  console.log(`${codeName} Started`);

  const router = express.Router();

  // Register routes
  router.post('/api/execEventType', execEventType);
  console.log(`${codeName} /api/execEventType registered`);

  router.post('/api/initialize', initializeController.initialize);
  console.log(`${codeName} /api/initialize registered`);

  router.get('/api/util/list-routes', (req, res) => {
    console.log(`${codeName} Entering /api/util/list-routes`);
    listRoutesController.listRoutes(app)(req, res);
  });
  console.log(`${codeName} /api/util/list-routes registered`);

  router.post('/api/util/restart-server', restartServerController.restartServer);
  console.log(`${codeName} /api/util/restart-server registered`);

  router.get('/api/util/fetchEventTypes', fetchEventTypes);
  console.log(`${codeName} /api/util/fetchEventTypes registered`);

  router.get('/api/util/apiColumns', fetchApiColumns);
  console.log(`${codeName} /api/util/apiColumns registered`);

  // Use the router in the app instance
  app.use('/', router);

  console.log(`${codeName} Routes setup complete`);
};

