require('module-alias/register');
require('dotenv').config(); // Load environment variables from .env file
const mysql = require('mysql2/promise');
const logger = require('./logger');
const fileName = '[dbUtils.js]';

// Initialize the connection pool
const pool = mysql.createPool({
  host: process.env.DB_HOST,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  port: process.env.DB_PORT,
  charset: process.env.DB_CHARSET,
  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0
});

/**
 * Executes a database query with proper error handling and logging
 * @param {string} query - SQL query to execute
 * @param {string} method - HTTP method (GET, POST, etc.)
 * @returns {Promise<Object>} Query results
 */
async function executeQuery(query, method = 'GET') {
    let connection;
    const start = process.hrtime();
    
    try {
        connection = await pool.getConnection();
        logger.debug(`${fileName} Executing ${method} query: ${query}`);

        let results;
        if (['POST', 'PATCH', 'DELETE'].includes(method)) {
            logger.debug(`${fileName} Handling ${method}-specific logic`);
            await connection.beginTransaction();
            results = await connection.execute(query);
            await connection.commit();
        } else if (method === 'GET') {
            logger.debug(`${fileName} Handling GET-specific logic`);
            const [rows] = await connection.execute(query);
            logger.info(`${fileName} Query executed, rows fetched: ${rows.length}`);
            results = rows;
        } else {
            throw new Error(`Unsupported method: ${method}`);
        }

        const [seconds, nanoseconds] = process.hrtime(start);
        const duration = seconds * 1000 + nanoseconds / 1000000;
        
        logger.logPerformance('database_query', duration, {
            method,
            rowCount: Array.isArray(results) ? results.length : undefined,
            success: true
        });

        return results;
    } catch (error) {
        const [seconds, nanoseconds] = process.hrtime(start);
        const duration = seconds * 1000 + nanoseconds / 1000000;
        
        logger.logPerformance('database_query', duration, {
            method,
            success: false,
            errorType: error.name,
            errorCode: error.code
        });

        logger.error(`${fileName} Error executing query:`, error);
        logger.error(`${fileName} Query: ${query}`);
        logger.error(`${fileName} Stack trace:`, new Error().stack);
        if (['POST', 'PATCH', 'DELETE'].includes(method) && connection) {
            await connection.rollback();
        }
        throw error;
    } finally {
        if (connection) {
            connection.release();
            logger.debug(`${fileName} Connection released`);
        }
    }
}

module.exports = { executeQuery };
