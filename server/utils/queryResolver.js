const logger = require('./logger');
const codeName = '[queryResolver.js]';

const replacePlaceholder = (qrySQL, paramName, paramValue) => {
  const regex = new RegExp(paramName, 'g');
  return qrySQL.replace(regex, paramValue);
};

const convertQuery = (qrySQL, params) => {
  try {
    // Log the original query and parameters
    logger.debug(`${codeName} Original query:`, { qrySQL, params });

    // Check for nested params and flatten if necessary
    if (params.params) {
      params = params.params;
    }

    // Directly replace placeholders in qrySQL with actual values from params
    for (const [paramName, paramValue] of Object.entries(params)) {
      logger.debug(`${codeName} Processing parameter:`, { paramName, paramValue });
      qrySQL = replacePlaceholder(qrySQL, paramName, typeof paramValue === 'string' ? `'${paramValue}'` : paramValue);
    }

    logger.debug(`${codeName} Modified query:`, qrySQL);
    return qrySQL;
  } catch (error) { 
    logger.error(`${codeName} Error converting query:`, error);
    throw new Error(`${codeName} Failed to convert query`);
  }
};

const createRequestBody = (qrySQL, params) => {
  const qryMod = convertQuery(qrySQL, params);
  logger.debug(`${codeName} Created request body with query:`, qryMod);
  return qryMod; // Return the string directly
};

module.exports = { createRequestBody };
