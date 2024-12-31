require('dotenv').config();
require('module-alias/register');
const mysql = require('mysql2/promise');

(async () => {
  try {
    // Log the environment variables to verify credentials
    console.log(`[Test Connection] Using credentials:`, {
      host: 'DB_HOST',
      user: 'DB_USER',
      password: 'password',
      database: process.env.DB_NAME,
      port: process.env.DB_PORT,
      charset: process.env.DB_CHARSET
    });

    // Create the connection using the correct configuration
    const connection = await mysql.createConnection({
      host: process.env.DB_HOST,
      user: process.env.DB_USER,
      password: process.env.DB_PASSWORD,
      database: process.env.DB_NAME,
      port: process.env.DB_PORT,
      charset: process.env.DB_CHARSET
    });

    console.log(`[Test Connection] Connected successfully`);
    const query = `SELECT name, description, id FROM ingredient_types WHERE account_id = 1 AND active = "Y" ORDER BY name`;
    const [rows] = await connection.execute(query);
    console.log(`[Test Connection] Query executed, rows fetched:`, rows);

    connection.end();
  } catch (error) {
    console.error(`[Test Connection] Error:`, error.message);
  }
})();
