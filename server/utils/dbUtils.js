// server/utils/dbUtils.js
const pool = require('../../db');

const executeQuery = async (query, params, res, codeName) => {
  try {
    const connection = await pool.getConnection();
    const [rows] = await connection.execute(query, params);
    connection.release();
    return rows;
  } catch (error) {
    throw new Error(`${codeName} Error executing query: ${error.message}`);
  }
};

module.exports = { executeQuery };
