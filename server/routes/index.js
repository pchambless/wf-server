require('module-alias/register');
const codeName = `[index.js] `;

console.log(codeName, 'Entering Index')
const router = require('@routes/registerRoutes'); // Import the centralized routes

const initializeRoutes = (app) => {
  app.use('/', router);
};

module.exports = { initializeRoutes }; 
