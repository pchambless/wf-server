const { executeQuery } = require('../utils/dbUtils');

const getApiColumns = async (req, res) => {
  const query = 'SELECT * FROM apiColumns';
  
  try {
    const result = await executeQuery(query, {});
    res.status(200).json(result);
  } catch (error) {
    console.error('[apiColumnsController] Error fetching apiColumns:', error);
    res.status(500).json({ message: 'Internal server error' });
  }
};

module.exports = { getApiColumns };
