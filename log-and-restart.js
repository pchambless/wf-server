const nodemon = require('nodemon');

nodemon({
  script: '/server/server.js',
  watch: ['server/controllers', 'server/routes', 'server/middleware', 'server/utils', 'server/app.js'],
  ignore: ['node_modules', 'logs', '*.log', 'apiTemplates', 'registry', 'api'],
  ext: 'js,json',
  delay: '10'
});

nodemon.on('start', function () {
  console.log('App has started');
}).on('quit', function () {
  console.log('App has quit');
  process.exit();
}).on('restart', function (files) {
  console.log('App restarted due to: ', files);
});
