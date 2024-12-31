const codeName = `[queryResolver.js] `;

const convertQuery = (qrySQL, params) => {
  try {
    console.log(codeName, 'Original qrySQL:', qrySQL);
    console.log(codeName, 'Original params:', params);

    // Ensure params are correctly formatted
    if (Array.isArray(params)) {
      params = params.reduce((acc, paramObj) => {
        Object.entries(paramObj).forEach(([key, value]) => {
          acc[`:${key}`] = typeof value === 'string' ? `'${value}'` : value;
        });
        return acc;
      }, {});
    } else {
      params = Object.entries(params).reduce((acc, [key, value]) => {
        acc[`:${key}`] = typeof value === 'string' ? `'${value}'` : value;
        return acc;
      }, {});
    }

    // Replace placeholders in qrySQL with actual values from params
    for (const [placeholder, value] of Object.entries(params)) {
      const regex = new RegExp(placeholder, 'g');
      qrySQL = qrySQL.replace(regex, value);
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

  const requestBody = {
    qryMod: qryMod
  };

  console.log(codeName, 'Created requestBody:', JSON.stringify(requestBody, null, 2));

  return requestBody;
};

module.exports = { createRequestBody };
