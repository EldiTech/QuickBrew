/**
 * Vercel Serverless Function - Dynamic App Configuration
 * Endpoint: /api/config
 */
module.exports = (req, res) => {
  // Disallow non-GET methods
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('Cache-Control', 'public, max-age=3600, stale-while-revalidate=86400');
  res.setHeader('X-Content-Type-Options', 'nosniff');

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
