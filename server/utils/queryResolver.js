const codeName = `[queryResolver.js]`;

const replacePlaceholder = (qrySQL, paramName, paramValue) => {
  const regex = new RegExp(paramName, 'g');
  return qrySQL.replace(regex, paramValue);
};

const convertQuery = (qrySQL, params) => {
  try {
    console.log(codeName, 'Original qrySQL:', qrySQL);
    console.log(codeName, 'Original params:', params);

    // Check for nested params and flatten if necessary
    if (params.params) {
      params = params.params;
    }

    // Directly replace placeholders in qrySQL with actual values from params
    for (const [paramName, paramValue] of Object.entries(params)) {
      console.log(codeName, 'ParamName: ', paramName, 'ParamVal: ', paramValue)
      qrySQL = replacePlaceholder(qrySQL, paramName, typeof paramValue === 'string' ? `'${paramValue}'` : paramValue);
    }

    console.log(codeName, 'qryMod:', qrySQL);
    return qrySQL;
  } catch (error) {
    console.error(codeName, 'Error converting query:', error);
    throw new Error(`${codeName} Failed to convert query`);
  }
};

const createRequestBody = (qrySQL, params) => {
  const qryMod = convertQuery(qrySQL, params);

  const requestBody = { qryMod };

  console.log(codeName, 'Created requestBody:', JSON.stringify(requestBody, null, 2));

  return requestBody;
};

module.exports = { createRequestBody };
