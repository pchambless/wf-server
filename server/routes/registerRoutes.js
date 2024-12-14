require('module-alias/register');
const express = require('express');
const mapEventTypeController = require('@controller/mapEventController');
const initializeController = require('@controller/initialize');
const listRoutesController = require('@controller/listRegisteredRoutes');
const restartServerController = require('@controller/restartServer');
const { fetchEventTypes } = require('@controller/fetchEventTypes');
const { getApiColumns } = require('@controller/apiColumnsController');
const codeName = '[registerRoutes]: ';

module.exports = (app) => {
  console.log(`${codeName} Started`);

  const router = express.Router();

  // Register routes
  router.post('/api/mapEventType', mapEventTypeController);
  console.log(`${codeName} /api/mapEventType registered`);

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

  router.get('/api/util/apiColumns', getApiColumns);
  console.log(`${codeName} /api/util/apiColumns registered`);

  // Middleware registration log
  app.use((req, res, next) => {
//    console.log(`${codeName} Processing ${req.method} ${req.path}`);
    next();
  });

  console.log(`${codeName} Routes setup complete`);
  return router;
};
