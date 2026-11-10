import './env.js';

import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

import { app } from './app.js';
import apiRoutes from './routes/apiRoutes.js';
import { renderPage, setRoutes } from './renderers/index.js';
import { callWorkflow } from './utils/n8nClient.js';

const codeName = '[server.js]';
const port = process.env.PORT || 3001;

// Cached routes (loaded at startup; see loadRoutesUntilReady)
let cachedRoutes = [];
let routesReady = false;

// Routes come from the database through n8n. After a reboot wf-server can start before n8n answers (task 866: every page was
// "Route not found" until a manual restart), so routes load in the background and retry: every 5 s for the first 2 minutes,
// then every 30 s until they load. Pages show a "starting up" notice meanwhile; /health and /api work from the start.
const FAST_RETRY_MS = 5000;
const FAST_RETRY_FOR_MS = 120000;
const SLOW_RETRY_MS = 30000;

async function fetchRoutes(query) {
  return callWorkflow('server-query', {
    query,
    params: {},
    source: 'server'
  });
}

// server-query answers "no rows" with [{}]; keep only rows that carry a route.
const routeRows = (data) => (Array.isArray(data) ? data.filter((r) => r && typeof r.route === 'string' && r.route) : []);

async function initializeRoutes() {
  const routeData = await fetchRoutes(`
    SELECT route, page_name, page_id, group_name
    FROM studio.api_routes()
  `);

  let routes = routeRows(routeData);

  if (routes.length === 0) {
    console.warn(`${codeName} api_routes() returned no routes. Falling back to studio.vw_pages.`);
    const fallbackRouteData = await fetchRoutes(`
      SELECT route_path as route, page_name, page_id, group_name
      FROM studio.vw_pages
      UNION ALL
      SELECT '/dashboard' as route, 'dashboard' as page_name, 32 as page_id, 'admin' as group_name
    `);
    routes = routeRows(fallbackRouteData);
  }

  if (routes.length === 0) return 0;

  console.log(`${codeName} Loaded ${routes.length} route(s):`);
  routes.forEach((r, idx) => {
    console.log(`${codeName}   [${idx + 1}] ${r.route} → ${r.page_name} (id: ${r.page_id})`);
  });

  cachedRoutes = routes;
  // Pass cached routes to pageRenderer
  setRoutes(cachedRoutes);
  routesReady = true;
  return routes.length;
}

async function loadRoutesUntilReady() {
  const startedAt = Date.now();
  for (let attempt = 1; ; attempt++) {
    try {
      if (await initializeRoutes() > 0) {
        if (attempt > 1) console.log(`${codeName} Routes loaded on attempt ${attempt}`);
        return;
      }
      console.warn(`${codeName} No routes loaded (attempt ${attempt}); retrying`);
    } catch (e) {
      console.error(`${codeName} Failed to load routes (attempt ${attempt}):`, e.message);
    }
    const wait = Date.now() - startedAt < FAST_RETRY_FOR_MS ? FAST_RETRY_MS : SLOW_RETRY_MS;
    await new Promise((resolve) => setTimeout(resolve, wait));
  }
}

// Page requests before the routes are loaded get a short "starting up" page instead of "Route not found".
function startingUp(req, res, next) {
  if (routesReady || req.method !== 'GET' || req.path === '/favicon.ico') return next();
  res.status(503).set('Retry-After', '10').type('html').send(
    '<!doctype html><html><head><meta charset="utf-8"><meta http-equiv="refresh" content="10"><title>WhatsFresh</title></head>'
    + '<body style="font-family:sans-serif;max-width:480px;margin:80px auto;text-align:center;color:#374151;">'
    + '<h2>WhatsFresh is starting up</h2><p>This page will try again in a few seconds.</p></body></html>'
  );
}

async function startServer() {
  try {
    // Load routes in the background; the server answers /health and /api meanwhile.
    loadRoutesUntilReady();

    // Register API routes (authVerify)
    app.use('/api', apiRoutes);

    // All other GET requests → generic page renderer (a "starting up" page until routes are loaded)
    app.get('{*path}', startingUp, renderPage);

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
