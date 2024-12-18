const mysql = require('mysql2/promise');

// Create a connection pool
const pool = mysql.createPool({
  host: process.env.DB_HOST,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME
});

const getConnection = async () => {
  return pool.getConnection();
};

const closeConnectionPool = async () => {
  await pool.end();
};

module.exports = { getConnection, closeConnectionPool };
