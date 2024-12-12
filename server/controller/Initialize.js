require('module-alias/register');
const path = require('path');

const generateEndpoints = () => {
  const scriptPath = path.join(__dirname, '../../apiTemplates/genEndpoints.js');
  require(scriptPath);
};

module.exports = {
  initialize: async (req, res) => {
    try {
      console.log('Starting initialization...');
      generateEndpoints();
      res.status(200).send('Initialization successful');
    } catch (error) {
      console.error('Error during initialization:', error);
      res.status(500).send('Initialization failed');
    }
  }
};
