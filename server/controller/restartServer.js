require('module-alias/register');
const { exec } = require('child_process');

module.exports = {
  restartServer: (req, res) => {
    console.log('Received request to restart the server.'); // Logging the request
    exec('pm2 restart wf-server', (error, stdout, stderr) => {
      if (error) {
        console.error(`Error restarting server: ${error}`);
        return res.status(500).send('Failed to restart the server.');
      }
      console.log(`Server restart output: ${stdout}`);
      res.send('Server restarted successfully.');
    });
  }
};
