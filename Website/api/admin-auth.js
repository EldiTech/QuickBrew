/**
 * QuickBrew Website Administration - Secure Serverless Authentication Gate
 * Endpoint: /api/admin-auth
 * 
 * Features:
 * 1. IP-based brute-force detection and progressive rate limiting
 * 2. Automated blocklist & lockdown on excessive failures or tampering
 * 3. Injection and malicious payload filtering (SQLi, XSS, Path Traversal)
 * 4. Timing-safe cryptographic credential verification (no plaintext leaks)
 * 5. HMAC-SHA256 cryptographically signed session tokens
 * 6. Audit incident ID generation for forensic tracking
 */

const crypto = require('crypto');

// Configuration Constants
const MAX_ATTEMPTS = 5;                        // Max allowed consecutive failed attempts
const ATTEMPT_WINDOW_MS = 15 * 60 * 1000;      // 15-minute sliding window
const STANDARD_LOCKOUT_MS = 30 * 60 * 1000;    // 30 minutes lockout for failed attempts
const SEVERE_LOCKOUT_MS = 60 * 60 * 1000;      // 1 hour lockout for malicious attack/tampering
const RAPID_FIRE_THRESHOLD_MS = 400;           // Faster than 400ms flagged as automated bot
const TOKEN_TTL_SECONDS = 2 * 60 * 60;         // 2-hour session lifetime

// Every secret comes from the environment and nowhere else. A fallback baked
// into this file is readable by anyone who can read the repository, and a
// known HMAC key lets them mint a valid super-admin token without a password.
// When any of these are unset the master login is simply off (fails closed);
// Firebase email sign-in still works.
//
//   ADMIN_SESSION_SECRET    random string, 32+ chars  (e.g. `openssl rand -hex 32`)
//   ADMIN_MASTER_USER       the master username
//   ADMIN_MASTER_PASS_HASH  scrypt$<salt hex>$<hash hex>
//                           — generate with: node scripts/hash_admin_password.js
const HMAC_SECRET = process.env.ADMIN_SESSION_SECRET || '';
const MASTER_USER = (process.env.ADMIN_MASTER_USER || '').trim().toLowerCase();
const MASTER_PASS_HASH = process.env.ADMIN_MASTER_PASS_HASH || '';
const MASTER_LOGIN_ENABLED =
  HMAC_SECRET.length >= 32 && MASTER_USER.length > 0 && MASTER_PASS_HASH.startsWith('scrypt$');
const MAX_FIELD_LENGTH = 256;

// In-Memory Rate Limiting & Blocklist Store
// Key: Client IP string
const ipRateStore = new Map();

/**
 * Periodically purge records older than 2 hours to avoid memory growth
 */
function pruneStaleRecords() {
  const now = Date.now();
  for (const [ip, entry] of ipRateStore.entries()) {
    if (entry.blockedUntil && entry.blockedUntil < now && (now - entry.lastAttemptAt) > 2 * 3600 * 1000) {
      ipRateStore.delete(ip);
    } else if (!entry.blockedUntil && (now - entry.lastAttemptAt) > ATTEMPT_WINDOW_MS) {
      ipRateStore.delete(ip);
    }
  }
}

/**
 * Extract clean client IP address.
 *
 * Prefers the headers Vercel's edge sets itself over a raw X-Forwarded-For,
 * whose leftmost entry is whatever the client chose to send — trusting it
 * would let anyone dodge the lockout, or lock out somebody else's IP.
 */
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

/**
 * Parse JSON request body safely
 */
async function parseBody(req) {
  if (req.body && typeof req.body === 'object') return req.body;
  if (typeof req.body === 'string') {
    try { return JSON.parse(req.body); } catch (_) { return {}; }
  }
  return new Promise((resolve) => {
    let raw = '';
    req.on('data', chunk => {
      raw += chunk;
      // Nothing this endpoint accepts is anywhere near this size.
      if (raw.length > 16 * 1024) { raw = ''; req.destroy(); resolve({}); }
    });
    req.on('end', () => {
      try { resolve(JSON.parse(raw || '{}')); }
      catch (_) { resolve({}); }
    });
  });
}

/**
 * Generate unique tracking Incident ID (e.g. SEC-BLK-A7C9-2F10)
 */
function generateIncidentId(prefix = 'BLK') {
  const rand = crypto.randomBytes(4).toString('hex').toUpperCase();
  const seg1 = rand.substring(0, 4);
  const seg2 = rand.substring(4, 8);
  return `SEC-${prefix}-${seg1}-${seg2}`;
}

/**
 * Check for malicious injection attacks in credentials/payloads
 */
function detectMaliciousPayload(str) {
  if (typeof str !== 'string') return false;
  // SQL Injection signatures
  const sqli = /('|"|;|--|\/\*|\*\/|union\s+select|select\s+.*\s+from|insert\s+into|drop\s+table|or\s+['"\d\w]+\s*=\s*['"\d\w]+)/i;
  // XSS and HTML probe signatures
  const xss = /(<[^>]*script.*?>|javascript:|vbscript:|onload\s*=|onerror\s*=|onclick\s*=|eval\s*\(|alert\s*\()/i;
  // Path traversal & command injection
  const pathTrav = /(\.\.\/|\.\.\\|\bexec\b|\bsystem\b|\$\{)/i;

  return sqli.test(str) || xss.test(str) || pathTrav.test(str);
}

/**
 * Timing-safe string comparison
 */
function safeEqual(a, b) {
  const bufA = Buffer.from(a || '', 'utf8');
  const bufB = Buffer.from(b || '', 'utf8');
  if (bufA.length !== bufB.length) return false;
  return crypto.timingSafeEqual(bufA, bufB);
}

/**
 * Check a password against a `scrypt$<salt hex>$<hash hex>` record. scrypt is
 * salted and deliberately slow, unlike a bare SHA-256, which can be reversed
 * for any ordinary password with a lookup table.
 */
function verifyPassword(password, record) {
  const parts = String(record).split('$');
  if (parts.length !== 3 || parts[0] !== 'scrypt') return false;
  try {
    const salt = Buffer.from(parts[1], 'hex');
    const expected = Buffer.from(parts[2], 'hex');
    if (salt.length < 16 || expected.length < 32) return false;
    const actual = crypto.scryptSync(String(password), salt, expected.length);
    return crypto.timingSafeEqual(actual, expected);
  } catch (_) {
    return false;
  }
}

/**
 * Issue cryptographically signed HMAC-SHA256 session token
 */
function createSessionToken(username, role, clientIp) {
  const header = { alg: 'HS256', typ: 'JWT' };
  const now = Math.floor(Date.now() / 1000);
  const ipHash = crypto.createHash('sha256').update(clientIp + HMAC_SECRET).digest('hex').substring(0, 16);

  const payload = {
    sub: username,
    displayName: 'AkoSiLuis (Super Admin)',
    role: role,
    iat: now,
    exp: now + TOKEN_TTL_SECONDS,
    ipFingerprint: ipHash
  };

  const encHeader = Buffer.from(JSON.stringify(header)).toString('base64url');
  const encPayload = Buffer.from(JSON.stringify(payload)).toString('base64url');
  const signature = crypto.createHmac('sha256', HMAC_SECRET)
    .update(`${encHeader}.${encPayload}`)
    .digest('base64url');

  return `${encHeader}.${encPayload}.${signature}`;
}

/**
 * Verify HMAC session token
 */
function verifySessionToken(token, clientIp) {
  if (!HMAC_SECRET) return { valid: false, reason: 'Master sessions are not configured' };
  if (!token || typeof token !== 'string' || token.length > 4096) return { valid: false, reason: 'Missing token' };
  const parts = token.split('.');
  if (parts.length !== 3) return { valid: false, reason: 'Malformed token structure' };

  const [encHeader, encPayload, signature] = parts;
  const expectedSig = crypto.createHmac('sha256', HMAC_SECRET)
    .update(`${encHeader}.${encPayload}`)
    .digest('base64url');

  if (!safeEqual(signature, expectedSig)) {
    return { valid: false, reason: 'Cryptographic signature mismatch (tampering detected)' };
  }

  try {
    const payload = JSON.parse(Buffer.from(encPayload, 'base64url').toString('utf8'));
    const now = Math.floor(Date.now() / 1000);

    if (payload.exp && payload.exp < now) {
      return { valid: false, reason: 'Session token expired' };
    }

    // Verify IP fingerprint
    const expectedIpHash = crypto.createHash('sha256').update(clientIp + HMAC_SECRET).digest('hex').substring(0, 16);
    if (payload.ipFingerprint && payload.ipFingerprint !== expectedIpHash) {
      return { valid: false, reason: 'Session bound to a different client origin' };
    }

    return { valid: true, payload };
  } catch (e) {
    return { valid: false, reason: 'Failed to decode token payload' };
  }
}

/**
 * Main Serverless Handler
 */
module.exports = async (req, res) => {
  // Disallow non-POST methods
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'Method not allowed' });
  }

  // Set strict security headers on response
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate');
  res.setHeader('Pragma', 'no-cache');
  res.setHeader('Expires', '0');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');

  pruneStaleRecords();

  const clientIp = getClientIp(req);
  const body = await parseBody(req);
  const now = Date.now();

  // Retrieve or initialize IP tracking record
  let record = ipRateStore.get(clientIp);
  if (!record) {
    record = {
      attempts: 0,
      firstAttemptAt: now,
      lastAttemptAt: now,
      blockedUntil: null,
      reason: '',
      incidentId: ''
    };
    ipRateStore.set(clientIp, record);
  }

  // Check if IP is currently blocked
  if (record.blockedUntil && record.blockedUntil > now) {
    const remainingSeconds = Math.ceil((record.blockedUntil - now) / 1000);
    return res.status(403).json({
      blocked: true,
      incidentId: record.incidentId,
      reason: record.reason || 'IP temporarily blocked due to excessive authentication failures or suspicious activity.',
      retryAfter: remainingSeconds,
      unlockTime: record.blockedUntil
    });
  } else if (record.blockedUntil && record.blockedUntil <= now) {
    // Block duration has expired: reset counters
    record.blockedUntil = null;
    record.attempts = 0;
    record.reason = '';
    record.incidentId = '';
  }

  // Reset window if elapsed
  if (now - record.firstAttemptAt > ATTEMPT_WINDOW_MS) {
    record.attempts = 0;
    record.firstAttemptAt = now;
  }

  const action = body.action || 'login';

  // =========================================================================
  // ACTION: check-status (Retrieve current rate limit status)
  // =========================================================================
  if (action === 'check-status') {
    return res.status(200).json({
      blocked: false,
      remainingAttempts: Math.max(0, MAX_ATTEMPTS - record.attempts),
      maxAttempts: MAX_ATTEMPTS
    });
  }

  // =========================================================================
  // ACTION: verify (Cryptographic Session Verification)
  // =========================================================================
  if (action === 'verify') {
    const token = body.token;
    const verifyResult = verifySessionToken(token, clientIp);

    if (!verifyResult.valid) {
      return res.status(401).json({
        valid: false,
        reason: verifyResult.reason
      });
    }

    return res.status(200).json({
      valid: true,
      user: verifyResult.payload.displayName || verifyResult.payload.sub,
      role: verifyResult.payload.role,
      expiresAt: verifyResult.payload.exp * 1000
    });
  }

  // =========================================================================
  // ACTION: report-tamper (Client reports unauthorized bypass or DOM tampering)
  // =========================================================================
  if (action === 'report-tamper') {
    const incidentId = generateIncidentId('TMP');
    record.blockedUntil = now + SEVERE_LOCKOUT_MS;
    // A fixed sentence, not the caller's: this text is stored and echoed back,
    // and also written to the server log, where a client-supplied string with
    // newlines in it could forge log lines.
    record.reason = 'Client-side security guard detected unauthorized session manipulation / bypass attempt.';
    record.incidentId = incidentId;

    const detail = String(body.reason || '').replace(/[\r\n\t]+/g, ' ').slice(0, 200);
    console.warn(`[SECURITY ALERT] Tamper attempt blocked from IP ${clientIp}. Incident: ${incidentId}. Detail: ${JSON.stringify(detail)}`);

    return res.status(403).json({
      blocked: true,
      incidentId: incidentId,
      reason: record.reason,
      retryAfter: Math.ceil(SEVERE_LOCKOUT_MS / 1000)
    });
  }

  // =========================================================================
  // ACTION: record-failure (Client reports external Firebase Auth failure)
  // =========================================================================
  if (action === 'record-failure') {
    record.attempts += 1;
    record.lastAttemptAt = now;

    if (record.attempts >= MAX_ATTEMPTS) {
      const incidentId = generateIncidentId('BLK');
      record.blockedUntil = now + STANDARD_LOCKOUT_MS;
      record.reason = 'Exceeded maximum permitted failed authentication attempts.';
      record.incidentId = incidentId;

      return res.status(429).json({
        blocked: true,
        incidentId: incidentId,
        reason: record.reason,
        retryAfter: Math.ceil(STANDARD_LOCKOUT_MS / 1000)
      });
    }

    return res.status(200).json({
      blocked: false,
      remainingAttempts: Math.max(0, MAX_ATTEMPTS - record.attempts)
    });
  }

  // =========================================================================
  // ACTION: login (Master Admin Authentication & Gatekeeper)
  // =========================================================================
  if (action === 'login') {
    // Coerced and capped: a non-string here would otherwise throw on .trim(),
    // and an unbounded password is unbounded scrypt work.
    const username = (typeof body.username === 'string' ? body.username : '').trim().slice(0, MAX_FIELD_LENGTH);
    const password = (typeof body.password === 'string' ? body.password : '').trim().slice(0, MAX_FIELD_LENGTH);

    // 1. Rapid fire bot detection (< 400ms between attempts)
    if (record.attempts > 0 && (now - record.lastAttemptAt) < RAPID_FIRE_THRESHOLD_MS) {
      const incidentId = generateIncidentId('BOT');
      record.blockedUntil = now + SEVERE_LOCKOUT_MS;
      record.reason = 'Automated high-speed request flood detected (bot defense triggered).';
      record.incidentId = incidentId;
      return res.status(403).json({
        blocked: true,
        incidentId: incidentId,
        reason: record.reason,
        retryAfter: Math.ceil(SEVERE_LOCKOUT_MS / 1000)
      });
    }

    // 2. Malicious payload inspection (SQLi / XSS / Path Traversal)
    if (detectMaliciousPayload(username) || detectMaliciousPayload(password)) {
      const incidentId = generateIncidentId('INJ');
      record.blockedUntil = now + SEVERE_LOCKOUT_MS;
      record.reason = 'Malicious injection payload detected in authentication request.';
      record.incidentId = incidentId;
      console.warn(`[SECURITY ALERT] Injection attempt from IP ${clientIp}. Incident: ${incidentId}`);
      return res.status(403).json({
        blocked: true,
        incidentId: incidentId,
        reason: record.reason,
        retryAfter: Math.ceil(SEVERE_LOCKOUT_MS / 1000)
      });
    }

    // 3. Verify Master Administrator Credentials
    // Both checks always run (when enabled) so a wrong username and a wrong
    // password take the same time to reject.
    const cleanUser = username.toLowerCase();
    let isMasterUser = false;
    let isMasterPass = false;
    if (MASTER_LOGIN_ENABLED && !username.includes('@')) {
      isMasterUser = safeEqual(cleanUser, MASTER_USER);
      isMasterPass = password.length > 0 && verifyPassword(password, MASTER_PASS_HASH);
    }

    if (isMasterUser && isMasterPass) {
      // SUCCESSFUL MASTER AUTHENTICATION
      // Reset rate limiter for this IP
      record.attempts = 0;
      record.blockedUntil = null;

      const token = createSessionToken(cleanUser, 'superadmin', clientIp);

      return res.status(200).json({
        success: true,
        token: token,
        displayName: 'AkoSiLuis (Super Admin)',
        role: 'superadmin',
        expiresIn: TOKEN_TTL_SECONDS
      });
    }

    // 4. If credentials don't match Master, check if it's an email (candidate for client Firebase Auth)
    if (username.includes('@')) {
      // Delegate authentication to client Firebase Auth, but report status
      return res.status(200).json({
        success: false,
        delegateToFirebase: true,
        remainingAttempts: Math.max(0, MAX_ATTEMPTS - record.attempts)
      });
    }

    // 5. Failed authentication attempt
    record.attempts += 1;
    record.lastAttemptAt = now;

    if (record.attempts >= MAX_ATTEMPTS) {
      const incidentId = generateIncidentId('BLK');
      record.blockedUntil = now + STANDARD_LOCKOUT_MS;
      record.reason = 'Maximum consecutive authentication attempts exceeded.';
      record.incidentId = incidentId;

      return res.status(429).json({
        success: false,
        blocked: true,
        incidentId: incidentId,
        message: 'Security lockout: Too many failed login attempts. Your IP has been temporarily blocked for 30 minutes.',
        retryAfter: Math.ceil(STANDARD_LOCKOUT_MS / 1000)
      });
    }

    const remaining = MAX_ATTEMPTS - record.attempts;
    return res.status(401).json({
      success: false,
      blocked: false,
      remainingAttempts: remaining,
      message: `Invalid administrator credentials. ${remaining} attempt${remaining === 1 ? '' : 's'} remaining before system lockout.`
    });
  }

  return res.status(400).json({ error: 'Unsupported action' });
};
