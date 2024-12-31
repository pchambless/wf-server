require('module-alias/register');
const path = require('path');
const envPath = path.resolve(__dirname, '../../.env'); // Adjusted path to root directory
console.log('Loading .env from:', envPath);
require('dotenv').config({ path: envPath });
const fs = require('fs');
const { exec } = require('child_process'); // Import child_process
const mysql = require('mysql2/promise'); // Import mysql2

// Debug: Log environment variables to ensure they are loaded correctly
console.log('DB_USER:', process.env.DB_USER);
console.log('DB_NAME:', process.env.DB_NAME);
console.log('DB_PORT:', process.env.DB_PORT);

// MySQL connection setup
const pool = mysql.createPool({
  host: process.env.DB_HOST,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  port: process.env.DB_PORT,
  charset: process.env.DB_CHARSET,
});

// Local executeQuery function
const executeQuery = async (query) => {
  let connection;
  try {
    console.log(`[runTests.js] Executing query: ${query}`);
    let results;
    connection = await pool.getConnection();

    await connection.beginTransaction();
    results = await connection.query(query);
    await connection.commit();

    return results;
  } catch (error) {
    console.error(`[runTests.js] Error executing query: ${error}`);
    if (connection) {
      await connection.rollback();
    }
    throw new Error(`[runTests.js] Error executing query: ${error.message}`);
  } finally {
    if (connection) {
      await connection.release();
      console.log(`[runTests.js] Connection released`);
    }
  }
};

// Function to escape strings for SQL queries
const escapeString = (value) => {
  return mysql.escape(value).replace(/^'|'$/g, ''); // Remove surrounding single quotes
};

// Paths to your JavaScript modules in the middleware
const eventTypesPath = path.join(__dirname, '../middleware/eventRoutes');
const apiColumnsPath = path.join(__dirname, '../middleware/apiColumns');

// Actual base URL
const baseUrl = 'http://localhost:3001/api/execEventType'; // Updated to the correct API endpoint

// Require the eventTypes and apiColumns modules
const eventTypes = require(eventTypesPath);
const apiColumns = require(apiColumnsPath);

// Helper function to get the value for a given variable name
function getValueForVariable(variableName) {
  const column = apiColumns.find(col => col.variableName === variableName);
  return column ? column.value : null;
}

// Function to resolve parameters with values from apiColumns and qrySQL
function resolveParams(eventType) {
  const resolvedParams = {};

  // Look in the params from eventRoutes
  const eventRoute = eventTypes.find(route => route.eventType === eventType.eventType);
  if (eventRoute) {
    const routeParams = JSON.parse(eventRoute.params); // Parse the params JSON string
    routeParams.forEach(param => {
      const value = getValueForVariable(param);
      if (value !== undefined && value !== null) {
        resolvedParams[param.slice(1)] = value;
      } else {
        resolvedParams[param.slice(1)] = param;
      }
    });
  }

  // Search the qrySQL for parameters
  const paramMatches = eventType.qrySQL.match(/:\w+/g);
  if (paramMatches) {
    paramMatches.forEach(param => {
      const value = getValueForVariable(param);
      if (value !== undefined && value !== null) {
        resolvedParams[param.slice(1)] = value;
      } else {
        resolvedParams[param.slice(1)] = param;
      }
    });
  }

  return resolvedParams;
}

// Helper function to validate JSON
function isValidJson(str) {
  try {
    JSON.parse(str);
  } catch (e) {
    return false;
  }
  return true;
}

// Function to execute curl commands and return status and details
async function runEventTypeTests(eventType) {
  console.log(`[runTests.js] Testing eventType:`, eventType);

  const resolvedParams = resolveParams(eventType);
  console.log(`[runTests.js] Resolved params: ${JSON.stringify(resolvedParams)}`);
  const eventTypeDetails = {
    eventType: eventType.eventType,
    params: resolvedParams,
  };

  return new Promise((resolve, reject) => {
    const jsonPayload = JSON.stringify(eventTypeDetails).replace(/\\/g, '\\\\').replace(/"/g, '\\"'); // Escape special characters and double quotes
    exec(`curl -X POST ${baseUrl} -H "Content-Type: application/json" -d "${jsonPayload}"`, (error, stdout, stderr) => {
      let details = stdout;
      let status = 'success';

      console.log(`[runTests.js] Curl response: ${stdout}`);
      if (error) {
        console.error(`[runTests.js] Error executing curl: ${error.message}`);
        details = error.message;
        status = 'failed';
      }

      if (!isValidJson(details)) {
        details = JSON.stringify('Internal server error');
      }

      console.log(`[runTests.js] Curl completed with status: ${status} and details: ${details}`);
      resolve({ status, details });
    });
  });
}

// Function to log the event type result
async function logEventTypeResult(eventType, status, details) {
  const query = `
    INSERT INTO apiTests (eventType, status, details)
    VALUES ('${eventType.eventType}', '${status}', '${escapeString(details)}')
    ON DUPLICATE KEY UPDATE 
      status = '${status}', 
      details = '${escapeString(details)}', 
      lastTest = CURRENT_TIMESTAMP`;

  console.log(`[runTests.js] Executing SQL Query: ${query}`);

  try {
    await executeQuery(query);
  } catch (error) {
    console.error(`[runTests.js] Error logging event type result: ${error.message}`);
  }
}

// Main function to run tests for all eventTypes
async function runTests() {
  try {
    console.log(`[runTests.js] Starting event type tests...`);
    for (const eventType of eventTypes) {
      const { status, details } = await runEventTypeTests(eventType);
      console.log(`[runTests.js] EventType: ${eventType.eventType}, Result: ${details}`);
      await logEventTypeResult(eventType, status, details);
    }
    console.log(`[runTests.js] All event type tests completed successfully.`);
  } catch (error) {
    console.error(`[runTests.js] Error during event type tests: ${error.message}`);
  } finally {
    // Ensure connection is closed and return control to terminal
    await pool.end();
    console.log(`[runTests.js] Connection pool ended`);
  }
}

// Ensure the runTests function call is reachable
runTests();
