let server;

const startServer = (app) => {
  server = app.listen(4000); // Ensure the server starts on the desired port
  global.__TEST_SERVER__ = server;
};

const closeServer = () => {
  if (server) {
    server.close();
  }
};

// Set up any initial parameters or data here
const setupDatabase = async () => {
  const userEmail = 'pc7900@gmail.com';
  const acctID = 1;

  // Store these values in a global object or database
  global.__TEST_DATA__ = {
    userEmail,
    acctID,
  };

  // If needed, you can add more setup logic here
};

module.exports = {
  startServer,
  closeServer,
  setupDatabase
};
