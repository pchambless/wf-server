require('dotenv').config(); // Load environment variables from .env file
const mysql = require('mysql2/promise');
const path = require('path');
const codeName = `[${path.basename(__filename)}] `;

const pool = mysql.createPool({
  host: process.env.DB_HOST,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  port: process.env.DB_PORT,
  charset: 'utf8mb4'
});

console.log(codeName, 'Connection Pool created.');

const getConnection = async () => {
  return pool.getConnection();
};

const closeConnectionPool = async () => {
  await pool.end();
};

module.exports = { getConnection, closeConnectionPool };
