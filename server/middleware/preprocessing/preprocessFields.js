// server/middleware/preprocessing/preprocessFields.js
const { getCurrentTimestamp, getCurrentUserID } = require('../../utils/timestamp');

const preprocessFields = (req, res, next) => {
  const userID = getCurrentUserID(req);
  const timestamp = getCurrentTimestamp();

  if (req.method === 'POST') {
    req.body.created_at = timestamp;
    req.body.created_by = userID;
  } else if (req.method === 'PATCH' || req.method === 'PUT') {
    req.body.updated_at = timestamp;
    req.body.updated_by = userID;
  }

  next();
};

module.exports = preprocessFields;
