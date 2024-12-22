const mysql = require('mysql2/promise');
const { host, user, password, database, port, charset } = require('./dbConfig');

// Create a connection pool using the extracted properties
const pool = mysql.createPool({
  host,
  user,
  password,
  database,
  port,
  charset
});

module.exports = {
  getConnection: async () => {
    return await pool.getConnection();
  }
};

