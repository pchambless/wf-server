import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

dotenv.config({ path: path.resolve(__dirname, '../.env') });

import { app } from './app.js';
import apiRoutes from './routes/apiRoutes.js';
import { renderPage } from './renderers/pageRenderer.js';
import { callWorkflow } from './utils/n8nClient.js';

const codeName = '[server.js]';
const port = process.env.PORT || 3001;

async function logAvailableRoutes() {
  try {
    const routeData = await callWorkflow('hydrate-guide', {
      template_name: 'api_routes', source: 'wf-server', format: 'json'
    });
    const routes = Array.isArray(routeData) ? routeData : routeData?.data || [];
    console.log(`${codeName} Available routes (${routes.length}):`);
    routes.forEach(r => console.log(`  ${r.route} (${r.page_name})`));
  } catch (e) {
    console.error(`${codeName} Failed to load routes:`, e.message);
  }
}

async function startServer() {
  try {
    // Log available routes at startup
    await logAvailableRoutes();

    // Register API routes (authVerify)
    app.use('/api', apiRoutes);

    // All other GET requests → generic page renderer
    app.get('{*path}', renderPage);

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
