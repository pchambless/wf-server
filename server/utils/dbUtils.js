const pool = require('../../db');
const mysql = require('mysql2/promise'); // Ensure mysql is imported
const codeName = '[dbUtils] ';

const replaceNamedParams = (query, params) => {
  const keys = Object.keys(params);
  keys.forEach(key => {
    query = query.replace(new RegExp(':' + key, 'g'), mysql.escape(params[key]));
  });
  return query;
};

const executeQuery = async (query, params, res) => {
  try {
    const connection = await pool.getConnection();

    // Replace named parameters with their corresponding values
    const formattedQuery = replaceNamedParams(query, params);

    // Log the formatted query
    console.log(codeName + `[executeQuery]  ${formattedQuery}`);

    const [rows] = await connection.execute(formattedQuery);
    connection.release();
    return rows;
  } catch (error) {
    console.error(codeName + `[executeQuery] ${codeName} Error executing query: ${error.message}`);
    throw new Error(`${codeName} Error executing query: ${error.message}`);
  }
};

module.exports = { executeQuery };
