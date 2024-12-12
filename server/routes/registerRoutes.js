require('module-alias/register');
const express = require('express');
const mapEventTypeController = require('@controller/mapEventController');
const initializeController = require('@controller/initialize');
const listRoutesController = require('@controller/listRegisteredRoutes');
const restartServerController = require('@controller/restartServer');
const { fetchEventTypes } = require('@controller/fetchEventTypes'); // Destructure to get fetchEventTypes function
const dynamicRouter = require('@apiTemplates/genEndpoints'); 
const codeName = '[registerRoutes]: ';

module.exports = (app) => {
  console.log(codeName + 'Started');
  const router = express.Router();

  console.log(codeName + '/api/mapEventType');
  router.post('/api/mapEventType', (req, res) => {
    mapEventTypeController(req, res);
  });

  router.post('/api/initialize', initializeController.initialize);
  
  router.get('/api/util/list-routes', (req, res) => {
    console.log('Entering /api/util/list-routes'); // Log for debugging
    listRoutesController.listRoutes(app)(req, res);
  });
  
  router.post('/api/util/restart-server', restartServerController.restartServer);
  
  // Add the new endpoint for fetching event types
  router.get('/api/util/event-types', fetchEventTypes); // Ensure this is a function

  // Register dynamic routes
  router.use(dynamicRouter);

  // Log to confirm route registration
  console.log('Routes registered');

  return router;
};
