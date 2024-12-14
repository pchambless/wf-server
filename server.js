require('module-alias/register');
const express = require('express');
const mysql = require('mysql2/promise');
const { app, port } = require('@root/server/app');
const registerRoutes = require('@routes/registerRoutes');
const { genEventTypeFile } = require('@controller/fetchEventTypes');

// Add middleware to set request timeout
app.use((req, res, next) => {
  req.setTimeout(5000); // 5 seconds timeout for testing
  next();
});

// Generate event types and initialize routes
const initializeServer = async () => {
  try {
    const connection = await mysql.createConnection({
      host: process.env.DB_HOST,
      user: process.env.DB_USER,
      password: process.env.DB_PASSWORD,
      database: process.env.DB_NAME
    });
    console.log('[server.js] Connected to the database successfully.');

    await genEventTypeFile(connection);
    console.log('[server.js] server/middleware/eventRoutes.js file generated.');

    // Initialize routes after eventRoutes.js is generated
    console.log('[server.js] Initializing routes');
    const router = registerRoutes(app);
    console.log('[server.js] Router returned from registerRoutes:', typeof router); // Log router type

    app.use('/', router); // Pass the app instance

    // Log after routes are initialized
    console.log('[server.js] Routes initialized');

    // Start the server
    console.log('[server.js] Attempting to start server on port', port);
    app.listen(port, () => {
      console.log(`[server.js] Server is running on http://localhost:${port}`);
    });

    const exitHandler = async () => {
      try {
        await connection.end();
        console.log('[server.js] Connection closed.');
        process.exit(0);
      } catch (error) {
        console.error('[server.js] Error during shutdown:', error);
        process.exit(1);
      }
    };

    process.on('SIGINT', exitHandler);
    process.on('SIGTERM', exitHandler);
  } catch (error) {
    console.error('[server.js] Error initializing server:', error);
    process.exit(1);
  }
};

initializeServer();
