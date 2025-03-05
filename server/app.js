const express = require('express');
const morgan = require('morgan');
const cors = require('cors');
const dotenv = require('dotenv');
const path = require('path');
const { 
  rateLimiter, 
  authRateLimiter, 
  securityHeaders, 
  corsOptions 
} = require('./middleware/security');
const errorHandler = require('./middleware/errorHandler');
const logger = require('./utils/logger');
const userLogin = require('./controller/userLogin'); // Import the userLogin controller
const execEventType = require('./controller/execEventType');
const codeName = `[app.js] `;

dotenv.config();

const app = express();
const port = process.env.PORT || 3001;

// Security middleware
app.use(securityHeaders); // Apply security headers
app.use(rateLimiter); // Apply general rate limiting
app.use('/api/auth/login', authRateLimiter); // Apply stricter rate limiting to login

// Configure morgan to skip certain requests and only log API calls
morgan.token('custom-status', (req, res) => {
  const status = res.statusCode;
  const color = status >= 500 ? 'red' : status >= 400 ? 'yellow' : 'green';
  return `\x1b[${color}m${status}\x1b[0m`;
});

// Custom morgan format - only log API calls and errors
app.use(morgan(':method :url :custom-status :response-time ms', {
  skip: (req) => {
    return req.path === '/favicon.ico' || 
           req.path === '/health' || 
           !req.path.startsWith('/api/') || 
           req.path === '/api/health';
  }
}));

// CORS and parsing middleware
app.use(cors(corsOptions));
app.use(express.json()); // Parse JSON request bodies
app.use(express.urlencoded({ extended: true })); // Parse URL-encoded bodies

// Add request received logging
app.use((req, res, next) => {
    logger.info(`${codeName} Request received: ${req.method} ${req.path}`);
    // Log request details for debugging
    logger.http(`${codeName} Request`, {
        method: req.method,
        path: req.path,
        headers: req.headers,
        body: req.body
    });
    next();
});

app.use(express.json({ limit: '10mb' })); // Limit JSON payload size
app.use(express.urlencoded({ extended: true, limit: '10mb' })); // Limit URL-encoded payload size

// Add parsing error handling
app.use((err, req, res, next) => {
    if (err instanceof SyntaxError && err.status === 400 && 'body' in err) {
        logger.error(`${codeName} JSON parsing error:`, err);
        return res.status(400).json({ 
            error: 'Bad Request',
            message: 'Invalid JSON payload'
        });
    }
    next(err);
});

// Serve static files if they exist
app.use(express.static(path.join(__dirname, 'public')));

logger.info(`${codeName} Application initialized`);

// Request performance monitoring middleware
app.use((req, res, next) => {
  const start = process.hrtime();

  // Override res.end to measure response time
  const originalEnd = res.end;
  res.end = function(...args) {
    const [seconds, nanoseconds] = process.hrtime(start);
    const duration = seconds * 1000 + nanoseconds / 1000000;

    // Only log performance metrics for non-static requests
    if (!req.path.includes('favicon.ico') && req.path !== '/health') {
      logger.logPerformance('http_request', duration, {
        method: req.method,
        path: req.path,
        status: res.statusCode
      });
    }

    originalEnd.apply(res, args);
  };

  next();
});

// Request logging middleware
app.use((req, res, next) => {
  // Skip logging for certain paths
  if (req.path === '/favicon.ico' || req.path === '/health') {
    return next();
  }

  // Log only essential request information
  const logData = {
    method: req.method,
    path: req.path
  };

  // Only include query parameters if they exist
  if (Object.keys(req.query).length > 0) {
    logData.query = req.query;
  }

  // Only log specific headers that are important
  const importantHeaders = ['user-agent', 'content-type'];
  const relevantHeaders = {};
  importantHeaders.forEach(header => {
    const value = req.get(header);
    if (value) {
      relevantHeaders[header] = value;
    }
  });

  if (Object.keys(relevantHeaders).length > 0) {
    logData.headers = relevantHeaders;
  }

  logger.http(`${codeName} Request`, logData);
  next();
});

// Basic health check endpoint
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'ok', timestamp: new Date().toISOString() });
});

// Root route handler
app.get('/', (req, res) => {
  res.status(200).json({
    status: 'success',
    message: 'WhatsNew API Server',
    version: '1.0.0',
    endpoints: {
      auth: {
        login: '/api/auth/login'
      },
      events: {
        execute: '/api/execEventType'
      },
      status: {
        health: '/health',
        database: '/api/status/database'
      }
    }
  });
});

// API routes are registered in registerRoutes.js
// Do not register routes here to avoid duplicates

// Error handling middleware
app.use(errorHandler);

module.exports = {
  app,
  port
};

// Note: 404 handler will be registered after routes in server.js
