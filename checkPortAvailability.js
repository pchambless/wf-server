const net = require('net');

const checkPort = (port) => {
  return new Promise((resolve, reject) => {
    const tester = net.createServer()
      .once('error', (err) => {
        if (err.code === 'EADDRINUSE') {
          reject(err);
        } else {
          resolve();
        }
      })
      .once('listening', () => {
        tester.once('close', () => {
          resolve();
        }).close();
      })
      .listen(port);
  });
};

checkPort(3002).then(() => {
  console.log('Port 3002 is available.');
  require('./server'); // Start your server
}).catch((err) => {
  console.error('Port 3002 is in use:', err);
});
