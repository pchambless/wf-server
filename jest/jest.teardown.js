const { closeServer } = require('./jestUtils');

module.exports = async () => {
  closeServer();
};
