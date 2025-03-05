// server/utils/logger.js
const winston = require('winston');
require('winston-daily-rotate-file');
const path = require('path');

const LOG_DIR = path.join(__dirname, '../logs');
const LOG_LEVEL = process.env.NODE_ENV === 'production' ? 'info' : 'debug';

// Performance monitoring format
const performanceFormat = winston.format((info) => {
  if (info.performance) {
    const { duration, ...rest } = info.performance;
    info.performance = {
      ...rest,
      duration: `${duration.toFixed(2)}ms`
    };
  }
  return info;
});

// Custom format for logs
const logFormat = winston.format.combine(
  winston.format.timestamp({ format: 'YYYY-MM-DD HH:mm:ss' }),
  winston.format.errors({ stack: true }),
  performanceFormat(),
  winston.format.splat(),
  winston.format.json()
);

// Console format with colors
const consoleFormat = winston.format.combine(
  winston.format.colorize(),
  winston.format.timestamp({ format: 'YYYY-MM-DD HH:mm:ss' }),
  performanceFormat(),
  winston.format.printf(({ level, message, timestamp, performance, ...metadata }) => {
    let msg = `${timestamp} [${level}]: ${message}`;
    if (performance) {
      msg += ` [Performance: ${performance.duration}]`;
    }
    if (Object.keys(metadata).length > 0) {
      msg += ` ${JSON.stringify(metadata, null, 2)}`;
    }
    return msg;
  })
);

// Rotating file transport configuration
const fileRotateTransport = new winston.transports.DailyRotateFile({
  filename: path.join(LOG_DIR, 'application-%DATE%.log'),
  datePattern: 'YYYY-MM-DD',
  maxSize: '20m',
  maxFiles: '14d',
  format: logFormat
});

// Error log rotating transport
const errorRotateTransport = new winston.transports.DailyRotateFile({
  filename: path.join(LOG_DIR, 'error-%DATE%.log'),
  datePattern: 'YYYY-MM-DD',
  maxSize: '20m',
  maxFiles: '14d',
  level: 'error',
  format: logFormat
});

// Performance log rotating transport
const performanceRotateTransport = new winston.transports.DailyRotateFile({
  filename: path.join(LOG_DIR, 'performance-%DATE%.log'),
  datePattern: 'YYYY-MM-DD',
  maxSize: '20m',
  maxFiles: '14d',
  format: logFormat
});

// Create the logger
const logger = winston.createLogger({
  level: LOG_LEVEL,
  format: logFormat,
  transports: [
    new winston.transports.Console({
      format: consoleFormat
    }),
    fileRotateTransport,
    errorRotateTransport,
    performanceRotateTransport
  ]
});

// Add event listeners for rotate events
fileRotateTransport.on('rotate', function(oldFilename, newFilename) {
  logger.info('Log file rotated', { oldFilename, newFilename });
});

// Utility function to measure performance
const measurePerformance = async (operation, func) => {
  const start = process.hrtime();
  try {
    return await func();
  } finally {
    const [seconds, nanoseconds] = process.hrtime(start);
    const duration = seconds * 1000 + nanoseconds / 1000000;
    logger.info(`Performance measurement for ${operation}`, {
      performance: { operation, duration }
    });
  }
};

// Export a wrapper with additional context methods
module.exports = {
  error: (message, ...args) => logger.error(message, ...args),
  warn: (message, ...args) => logger.warn(message, ...args),
  info: (message, ...args) => logger.info(message, ...args),
  http: (message, ...args) => logger.http(message, ...args),
  debug: (message, ...args) => logger.debug(message, ...args),
  // Add method to change log level dynamically
  setLogLevel: (level) => {
    logger.level = level;
  },
  // Add method to get current logger configuration
  getLoggerConfig: () => ({
    level: logger.level,
    logDir: LOG_DIR,
    maxSize: '20m',
    maxFiles: '14d'
  }),
  // Add performance measurement utility
  measurePerformance,
  // Add method to log performance metrics
  logPerformance: (operation, duration, metadata = {}) => {
    logger.info(`Performance measurement for ${operation}`, {
      performance: { operation, duration, ...metadata }
    });
  }
};
