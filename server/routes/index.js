require('module-alias/register');
const router = require('@routes/registerRoutes'); // Import the centralized routes

const initializeRoutes = (app) => {
  app.use('/', router);
};

module.exports = { initializeRoutes };
