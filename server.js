require('module-alias/register');
const express = require('express');
const { app, port } = require('@root/server/app');
const mysql = require('mysql2/promise');
const { genEventTypeFile } = require('@root/server/middleware/events/genEventTypes');
const { initializeRoutes } = require('@root/server/routes/index');
const eventRoutes = require('@middleware/events/eventRoutes');

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
    initializeRoutes(app);

    // Add route to list all registered routes for debugging
    app.get('/api/list-routes', (req, res) => {
      const routes = eventRoutes.map(route => {
        const methods = [route.method.toUpperCase()];
        return {
          path: route.path,
          methods,
          params: route.params,
          bodyCols: route.bodyCols,
          qrySQL: route.qrySQL
        };
      });

      res.json({ routes });
    });

    // Start the server
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
