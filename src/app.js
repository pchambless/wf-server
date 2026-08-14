import express from 'express';
import morgan from 'morgan';
import cors from 'cors';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';
import session from 'express-session';
import SessionFileStore from 'session-file-store';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const FileStore = SessionFileStore(session);

const app = express();

// Behind Caddy in both dev and prod - needed so `cookie.secure: 'auto'` can
// tell HTTPS-terminated-at-proxy requests apart from local plain-http runs.
app.set('trust proxy', 1);

app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      scriptSrc: ["'self'", "'unsafe-inline'", "https://unpkg.com"],
      styleSrc: ["'self'", "'unsafe-inline'"],
      imgSrc: ["'self'", "data:"],
      connectSrc: ["'self'", process.env.N8N_BASE_URL || "https://n8n.whatsfresh.app"]
    }
  }
}));
app.use(rateLimit({ windowMs: 15 * 60 * 1000, max: 500 }));

app.use(morgan('dev', {
  skip: (req) => req.path === '/favicon.ico' || req.path === '/health'
}));

app.use(cors());
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

const SESSION_MAX_AGE_MS = 24 * 60 * 60 * 1000;

app.use(session({
  store: new FileStore({
    path: path.join(__dirname, '..', '.sessions'),
    ttl: SESSION_MAX_AGE_MS / 1000,
    logFn: () => {}
  }),
  secret: process.env.SESSION_SECRET || 'change-me-in-production',
  resave: false,
  saveUninitialized: false,
  // 'auto' sets Secure only when the request (or the trusted proxy in front
  // of it) is HTTPS, so local http dev keeps working while prod behind
  // Caddy gets a real Secure cookie.
  cookie: { secure: 'auto', httpOnly: true, maxAge: SESSION_MAX_AGE_MS }
}));

app.use(express.static(path.join(__dirname, '..', 'public')));

app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

app.use((err, req, res, next) => {
  if (err instanceof SyntaxError && err.status === 400) {
    return res.status(400).json({ error: 'Invalid JSON payload' });
  }
  console.error(err);
  res.status(err.status || 500).json({ error: err.message || 'Internal Server Error' });
});

export { app };
