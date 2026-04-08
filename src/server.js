import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

dotenv.config({ path: path.resolve(__dirname, '../.env') });

import { app } from './app.js';
import apiRoutes from './routes/apiRoutes.js';

const codeName = '[server.js]';
const port = process.env.PORT || 3001;

async function startServer() {
  try {
    // Register API routes (authVerify)
    app.use('/api', apiRoutes);

    // All other GET requests → generic page renderer
    app.get('*', renderPage);

    app.use((req, res) => {
      if (req.path !== '/favicon.ico') {
        console.warn(`${codeName} Route not found: ${req.method} ${req.path}`);
      }
      res.status(404).json({ error: 'Route not found' });
    });

    const server = app.listen(port, () => {
      console.log(`${codeName} Running on http://localhost:${port}`);
    });

    server.keepAliveTimeout = 5000;
    server.headersTimeout = 6000;

    process.on('SIGTERM', () => {
      console.log(`${codeName} SIGTERM — shutting down`);
      server.close(() => process.exit(0));
    });

  } catch (error) {
    console.error(`${codeName} Startup failed:`, error);
    process.exit(1);
  }
}

startServer();
