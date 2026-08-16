// pm2 process definition for wf-server on the DEV droplet.
//
// Why this file exists: pm2's settings previously lived only in the pm2 daemon's
// saved state on the droplet, invisible to this repo. Nobody could see how the
// process was configured without SSHing in and running `pm2 describe`, and a
// setting changed by hand on the box would never show up in a diff or a review.
//
// Production does NOT use this file - prod runs wf-server under systemd
// (/etc/systemd/system/wf-server.service, WorkingDirectory=/root/wf-server) and
// is restarted by scripts/production/prod_deploy.sh. Only the dev droplet is
// pm2-managed.
//
// .cjs, not .js, because package.json sets "type": "module" and pm2 loads this
// file with require().

module.exports = {
  apps: [
    {
      name: 'wf-server',
      script: 'src/server.js',

      // Resolve relative to this file so the config is not tied to one path.
      cwd: __dirname,

      exec_mode: 'fork',
      instances: 1,

      // The server reads its config via node's own --env-file rather than a
      // dotenv import, because dotenv.config() written above an import still
      // runs after it (ESM hoisting) - that once made prod silently call dev's
      // n8n. Keep this flag.
      node_args: '--env-file=.env',

      autorestart: true,

      // WATCH MUST STAY FALSE. This is a deploy target, not a dev box:
      // scripts/deploy.sh restarts the process explicitly, so watching is
      // redundant. It is also actively harmful. pm2's watcher covers the whole
      // cwd, and task 245 moved express-session to a file store writing
      // .sessions/<id>.json - so with watch on, EVERY LOGIN wrote a file that
      // restarted the server mid-request. That surfaced as Cloudflare 502/520s,
      // "Unexpected token '<'" in the browser (an HTML error page parsed as
      // JSON), a missing appbar, and 438,411 pm2 restarts before it was found
      // on 2026-08-16.
      //
      // If watch is ever genuinely needed here, ignore_watch must exclude
      // '.sessions' and 'logs' at minimum - but prefer leaving this false.
      watch: false
    }
  ]
};
