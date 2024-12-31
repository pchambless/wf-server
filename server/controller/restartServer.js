require('module-alias/register');
const { exec } = require('child_process');
const codeName = '[restartServer.js] ';

module.exports = {
  restartServer: (req, res) => {
    console.log(`${codeName} Received request to restart the server.`); // Logging the request
    exec('pm2 restart wf-server', (error, stdout, stderr) => {
      if (error) {
        console.error(`${codeName} Error restarting server: ${error}`);
        return res.status(500).send(`${codeName} Failed to restart the server.`);
      }
      console.log(`Server restart output: ${stdout}`);
      res.send('Server restarted successfully.');
    });
  }
};
