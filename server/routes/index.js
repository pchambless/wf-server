require('module-alias/register');
const path = require('path');
const codeName = `[${path.basename(__filename)}] `;

console.log(codeName, 'Entering Index')
const router = require('@routes/registerRoutes'); // Import the centralized routes

const initializeRoutes = (app) => {
  app.use('/', router);
};

module.exports = { initializeRoutes };
