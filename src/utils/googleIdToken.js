import crypto from 'crypto';

// Verifies a Google Sign-In ID token (a JWT signed by Google) with Node's own crypto: no Google library, and no
// Google token is ever stored. Google's public keys rotate; they are cached for the max-age Google sends.
const CERTS_URL = 'https://www.googleapis.com/oauth2/v3/certs';
const ISSUERS = new Set(['accounts.google.com', 'https://accounts.google.com']);
const CLOCK_SKEW_S = 300;

let keyCache = { keys: new Map(), expiresAt: 0 };

async function loadKeys(force = false) {
  if (!force && Date.now() < keyCache.expiresAt && keyCache.keys.size) return keyCache.keys;
  const res = await fetch(CERTS_URL);
  if (!res.ok) throw new Error(`google certs fetch failed: ${res.status}`);
  const { keys = [] } = await res.json();
  const maxAge = Number(/max-age=(\d+)/.exec(res.headers.get('cache-control') || '')?.[1] || 3600);
  const map = new Map();
  for (const jwk of keys) {
    if (jwk.kid && jwk.kty === 'RSA') map.set(jwk.kid, crypto.createPublicKey({ key: jwk, format: 'jwk' }));
  }
  keyCache = { keys: map, expiresAt: Date.now() + maxAge * 1000 };
  return map;
}

const b64urlJson = (part) => JSON.parse(Buffer.from(part, 'base64url').toString('utf8'));

// Returns the token's claims when it is genuine, unexpired, issued by Google for this client, and the email is
// verified. Throws otherwise; the message is for logs, not for the user.
export async function verifyGoogleIdToken(idToken, clientId, { getKeys = loadKeys, now = Date.now } = {}) {
  if (!clientId) throw new Error('GOOGLE_CLIENT_ID not set');
  if (typeof idToken !== 'string' || idToken.length > 4096) throw new Error('malformed token');
  const parts = idToken.split('.');
  if (parts.length !== 3) throw new Error('malformed token');

  let header, claims;
  try {
    header = b64urlJson(parts[0]);
    claims = b64urlJson(parts[1]);
  } catch {
    throw new Error('malformed token');
  }
  if (header.alg !== 'RS256' || !header.kid) throw new Error('unexpected token algorithm');

  let keys = await getKeys();
  if (!keys.has(header.kid)) keys = await getKeys(true); // Google rotated its keys since the cache was filled
  const key = keys.get(header.kid);
  if (!key) throw new Error('unknown signing key');

  const signed = Buffer.from(`${parts[0]}.${parts[1]}`);
  const signature = Buffer.from(parts[2], 'base64url');
  if (!crypto.verify('RSA-SHA256', signed, key, signature)) throw new Error('bad signature');

  const nowS = Math.floor(now() / 1000);
  if (!ISSUERS.has(claims.iss)) throw new Error('wrong issuer');
  if (claims.aud !== clientId) throw new Error('wrong audience');
  if (typeof claims.exp !== 'number' || claims.exp + CLOCK_SKEW_S < nowS) throw new Error('token expired');
  if (typeof claims.iat === 'number' && claims.iat - CLOCK_SKEW_S > nowS) throw new Error('token issued in the future');
  if (claims.email_verified !== true && claims.email_verified !== 'true') throw new Error('email not verified');
  if (!claims.email) throw new Error('no email in token');

  return claims;
}
