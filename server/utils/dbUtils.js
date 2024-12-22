const executeQuery = async (query, params, method) => {
  try {
    console.log(`[executeQuery] Executing query: ${query}`);
    console.log(`[executeQuery] With params: ${JSON.stringify(params)}`);
    console.log(`[executeQuery] Method: ${method}`);

    let results;

    // Handle method-specific logic
    if (method === 'POST') {
      console.log('[executeQuery] Handling POST-specific logic');
      // Begin transaction for POST requests
      await db.beginTransaction();
      results = await db.query(query, params);
      await db.commit();
    } else if (method === 'PATCH') {
      console.log('[executeQuery] Handling PATCH-specific logic');
      // Update existing data
      results = await db.query(query, params);
    } else if (method === 'GET') {
      console.log('[executeQuery] Handling GET-specific logic');
      // Retrieve data
      results = await db.query(query, params);
    } else {
      throw new Error(`Unsupported method: ${method}`);
    }

    return results;
  } catch (error) {
    console.error('[executeQuery] Error executing query:', error);
    // Rollback if a transaction was started for a POST request
    if (method === 'POST') {
      await db.rollback();
    }
    throw new Error(`Error executing query: ${error.message}`);
  }
};

module.exports = { executeQuery };
