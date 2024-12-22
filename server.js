require('module-alias/register');
const mysql = require('mysql2/promise');
const { app, port } = require('@root/server/app');
const registerRoutes = require('@routes/registerRoutes');
const { genEventTypeFile } = require('@controller/fetchEventTypes');
const { genApiColumnFile } = require('@controller/apiColumnsController');
const path = require('path');
const codeName = `[${path.basename(__filename)}] `;

// Add middleware to set request timeout
app.use((req, res, next) => {
  req.setTimeout(10000); // 10 seconds timeout for testing
  next();
});

// Simple test route to verify routing
app.get('/test-route', (req, res) => {
  res.send('Test route is working!');
});

const initializeServer = async () => {
  try {
    const connection = await mysql.createConnection({
      host: process.env.DB_HOST,
      user: process.env.DB_USER,
      password: process.env.DB_PASSWORD,
      database: process.env.DB_NAME
    });
    console.log(codeName, 'Connected to the database successfully.');

    await genEventTypeFile(connection);
    await genApiColumnFile(connection);

    // Initialize routes after eventRoutes.js is generated
    console.log(codeName, 'Initializing routes');
    registerRoutes(app); // Register routes
    console.log(codeName, 'Routes initialized');

    // Start the server
    console.log(codeName, 'Attempting to start server on port', port);
    app.listen(port, () => {
      console.log(codeName, `Server is running on http://localhost:${port}`);
    });

    const exitHandler = async () => {
      try {
        await connection.end();
        console.log(codeName, 'Connection closed.');
        process.exit(0);
      } catch (error) {
        console.error(codeName, 'Error during shutdown:', error);
        process.exit(1);
      }
    };

    process.on('SIGINT', exitHandler);
    process.on('SIGTERM', exitHandler);
  } catch (error) {
    console.error(codeName, 'Error initializing server:', error);
    process.exit(1);
  }
};

initializeServer();
