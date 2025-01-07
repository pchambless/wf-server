// server/utils/logger.js
const logAndTime = (fileName, message) => {
  const timestamp = new Date().toISOString();
  console.log(`[${fileName}] ${timestamp} - ${message}`);
};

module.exports = logAndTime;
