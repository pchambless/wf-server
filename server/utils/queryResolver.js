const codeName = `[queryResolver.js] `;

const convertQuery = (qrySQL, params) => {
  try {
    console.log(codeName, 'Original query:', qrySQL);
    console.log(codeName, 'Original params:', params);

    // Check if params is an array and map to an object with placeholders as keys
    if (Array.isArray(params)) {
      const placeholders = qrySQL.match(/:\w+/g);
      params = placeholders.reduce((acc, placeholder, index) => {
        acc[placeholder] = params[index];
        return acc;
      }, {});
    }

    // Replace placeholders in qrySQL with actual values from params
    for (const [placeholder, value] of Object.entries(params)) {
      const regex = new RegExp(placeholder, 'g');
      qrySQL = qrySQL.replace(regex, value);
    }

    console.log(codeName, 'Converted query:', qrySQL);
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
