require('module-alias/register');

module.exports = {
  initialize: async (req, res) => {
    try {
      console.log('Starting initialization...');
      // Any other initialization logic can go here
      res.status(200).send('Initialization successful');
    } catch (error) {
      console.error('Error during initialization:', error);
      res.status(500).send('Initialization failed');
    }
  }
};
