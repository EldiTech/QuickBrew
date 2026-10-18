/**
 * Vercel Serverless Function - Dynamic App Configuration
 * Endpoint: /api/config
 * Hardened with IP-based rate limiting & security headers
 */

const configRateLimit = new Map();
const RATE_LIMIT_MAX = 60; // Max 60 requests per minute
const RATE_LIMIT_WINDOW = 60 * 1000;

// Vercel's own headers first: the leftmost X-Forwarded-For entry is whatever
// the client sent, so keying on it would let one caller mint a fresh bucket
// (and a fresh map entry) per request.
function getClientIp(req) {
  const first = (v) => String(Array.isArray(v) ? v[0] : v).split(',')[0].trim();
  const vercel = req.headers['x-vercel-forwarded-for'];
  if (vercel) return first(vercel);
  const real = req.headers['x-real-ip'];
  if (real) return first(real);
  const forwarded = req.headers['x-forwarded-for'];
  if (forwarded) return first(forwarded);
  return req.socket?.remoteAddress || '127.0.0.1';
}

function pruneExpired(now) {
  for (const [ip, entry] of configRateLimit) {
    if (now - entry.start > RATE_LIMIT_WINDOW) configRateLimit.delete(ip);
  }
}

module.exports = (req, res) => {
  // Disallow non-GET methods
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    res.setHeader('Allow', 'GET, HEAD');
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const now = Date.now();
  if (configRateLimit.size > 5000) pruneExpired(now);
  const ip = getClientIp(req);
  let record = configRateLimit.get(ip);
  if (!record || (now - record.start) > RATE_LIMIT_WINDOW) {
    record = { count: 1, start: now };
    configRateLimit.set(ip, record);
  } else {
    record.count++;
  }

  if (record.count > RATE_LIMIT_MAX) {
    res.setHeader('Retry-After', '60');
    return res.status(429).json({ error: 'Too many requests. Please slow down.' });
  }

  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('Cache-Control', 'public, max-age=3600, stale-while-revalidate=86400');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');

  // De-obfuscate securely on server or read environment variables
  const getVal = (envKey, b64Fallback) => {
    if (process.env[envKey]) return process.env[envKey];
    return Buffer.from(b64Fallback, 'base64').toString('utf8');
  };

  const config = {
    apiKey: getVal('FIREBASE_API_KEY', 'QUl6YVN5RGx4bVVxV1RhZEZBQ0p2UUVrWm13R3B4el9fM3Buamtr'),
    appId: getVal('FIREBASE_APP_ID', 'MToxMDM5NTYzNTczNjkyOndlYjo5Y2UyZGFmNDM3M2JlNzY4ZGZjM2I5'),
    messagingSenderId: '1039563573692',
    projectId: 'quick-brew-64673',
    authDomain: 'quick-brew-64673.firebaseapp.com',
    storageBucket: 'quick-brew-64673.firebasestorage.app'
  };

  return res.status(200).json(config);
};
