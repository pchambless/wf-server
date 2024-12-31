require('module-alias/register');
require('dotenv').config(); // Load environment variables from .env file
const mysql = require('mysql2/promise');
const codeName = '[dbUtils.js] ';

const executeQuery = async (query, method) => {
  let connection;
  try {
    console.log(`${codeName} Executing ${method} query: ${query}`);

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
      console.log(`${codeName} handling ${method}-specific logic`);
      await connection.beginTransaction();
      results = await connection.query(query);
      await connection.commit();
    } else if (method === 'GET') {
      console.log(`${codeName} handling GET-specific logic`);
      const [rows] = await connection.execute(query);
      console.log(`${codeName} Query executed, rows fetched: ${rows.length}`);
      results = rows;
    } else {
      throw new Error(`${codeName} Unsupported method: ${method}`);
    }

    return results;
  } catch (error) {
    console.error(`${codeName} Error executing query: ${error}`);
    if (['POST', 'PATCH', 'DELETE'].includes(method) && connection) {
      await connection.rollback();
    }
    throw new Error(`${codeName} Error executing query: ${error.message}`);
  } finally {
    if (connection) {
      await connection.end(); // Ensure connection is closed
      console.log(`${codeName} Connection closed`);
    }
  }
};

module.exports = { executeQuery };
