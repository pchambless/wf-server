const mysql = require('mysql2/promise');
const dbConfig = require('./config/dbConfig'); // Corrected path to dbConfig.js

const pool = mysql.createPool(dbConfig);

module.exports = {
  getConnection: async () => {
    return await pool.getConnection();
  }
};
