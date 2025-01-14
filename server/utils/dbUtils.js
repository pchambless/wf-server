require('module-alias/register');
require('dotenv').config(); // Load environment variables from .env file
const mysql = require('mysql2/promise');
const fileName = '[dbUtils.js] ';

/**
 * Executes a database query based on the specified HTTP method.
 * Handles connection creation, transaction management, and error handling.
 *
 * @async
 * @param {string} query - The SQL query to execute.
 * @param {string} method - The HTTP method (GET, POST, PATCH, DELETE) associated with the query.
 * @returns {Promise<*>} The results of the query execution.
 * @throws {Error} If there's an error during query execution or if the method is unsupported.
 */
const executeQuery = async (query, method) => {
  let connection;
  try {
    console.log(`${fileName}Executing ${method} query: ${query}`);

    let results;

    connection = await mysql.createConnection({
      host: process.env.DB_HOST,
      user: process.env.DB_USER,
      password: process.env.DB_PASSWORD,
      database: process.env.DB_NAME,
      port: process.env.DB_PORT,
      charset: process.env.DB_CHARSET
    });

    if (['POST', 'PATCH', 'DELETE'].includes(method)) {
      console.log(`${fileName}Handling ${method}-specific logic`);
      await connection.beginTransaction();
      results = await connection.query(query);
      await connection.commit();
    } else if (method === 'GET') {
      console.log(`${fileName}Handling GET-specific logic`);
      const [rows] = await connection.execute(query);
      console.log(`${fileName}Query executed, rows fetched: ${rows.length}`);
      results = rows;
    } else {
      throw new Error(`${fileName}Unsupported method: ${method}`);
    }

    return results;
  } catch (error) {
    console.error(`${fileName}Error executing query: ${error}`);
    if (['POST', 'PATCH', 'DELETE'].includes(method) && connection) {
      await connection.rollback();
    }
    throw new Error(`${fileName}Error executing query: ${error.message}`);
  } finally {
    if (connection) {
      await connection.end(); // Ensure connection is closed
      console.log(`${fileName}Connection closed`);
    }
  }
};

module.exports = { executeQuery };
