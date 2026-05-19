import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

dotenv.config({ path: path.resolve(__dirname, '../.env') });

import { app } from './app.js';
import apiRoutes from './routes/apiRoutes.js';
import { renderPage, setRoutes } from './renderers/index.js';
import { callWorkflow } from './utils/n8nClient.js';

const codeName = '[server.js]';
const port = process.env.PORT || 3001;

// Cached routes (loaded once at startup)
let cachedRoutes = [];

async function fetchRoutes(query) {
  return callWorkflow('server-query', {
    query,
    params: {},
    source: 'server'
  });
}

async function initializeRoutes() {
  try {
    const routeData = await fetchRoutes(`
      SELECT route, page_name, id AS page_id
      FROM studio.api_routes()
      UNION ALL
      SELECT '/whatsfresh' as route, 'wf-dashboard' as page_name, 32 as page_id
    `);

    cachedRoutes = Array.isArray(routeData) ? routeData : [];

    if (cachedRoutes.length === 0) {
      console.warn(`${codeName} api_routes() returned no routes. Falling back to studio.vw_pages.`);
      const fallbackRouteData = await fetchRoutes(`
        SELECT route_path as route, page_name, page_id
        FROM studio.vw_pages
        UNION ALL
        SELECT '/whatsfresh' as route, 'wf-dashboard' as page_name, 32 as page_id
      `);
      cachedRoutes = Array.isArray(fallbackRouteData) ? fallbackRouteData : [];
    }

    console.log(`${codeName} Loaded ${cachedRoutes.length} route(s):`);
    if (cachedRoutes.length === 0) {
      console.warn(`${codeName} WARNING: No routes loaded. routeData:`, routeData);
    } else {
      cachedRoutes.forEach((r, idx) => {
        console.log(`${codeName}   [${idx + 1}] ${r.route} → ${r.page_name} (id: ${r.page_id})`);
      });
    }

    // Pass cached routes to pageRenderer
    setRoutes(cachedRoutes);
  } catch (e) {
    console.error(`${codeName} Failed to initialize routes:`, e.message);
  }
}

async function startServer() {
  try {
    // Initialize routes once at startup
    await initializeRoutes();

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
