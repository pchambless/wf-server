// server/utils/timestamp.js
const getCurrentTimestamp = () => new Date().toISOString();
const getCurrentUserID = (req) => req.user.id;

module.exports = {
  getCurrentTimestamp,
  getCurrentUserID
};
