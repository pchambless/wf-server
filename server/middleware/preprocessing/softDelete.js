// server/middleware/preprocessing/softDelete.js
require('module-alias/register');
const { softDelete } = require('@utils/softDelete');

const handleSoftDelete = async (req, res, next) => {
  const { tableName, recordId } = req.body;
  const userId = req.user.id;

  const result = await softDelete(tableName, recordId, userId);
  if (result.success) {
    res.json({ success: true, message: result.message });
  } else {
    res.status(500).json({ success: false, message: result.message });
  }
};

module.exports = handleSoftDelete;
