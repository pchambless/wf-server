const { setupDatabase } = require('./jestUtils');

module.exports = async () => {
  // Set up the database without starting the server again
  await setupDatabase();
};
