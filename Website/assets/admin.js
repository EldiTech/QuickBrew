/**
 * QuickBrew Website Admin Console - Logic & CMS Controller
 * Focus: Website traffic, APK releases, landing page copy, and announcements
 */

// Default Website Configuration Settings
const DEFAULT_WEB_CONFIG = {
  versionTag: 'v1.0.0 Stable',
  buildNumber: '1.0.0+1',
  apkSize: '55.1 MB',
  minAndroid: 'Android 6.0+ (Marshmallow)',
  apkFileName: 'quickbrew-release.apk',
  checksum: 'CFAD5848B2287D5BE537E88DB1FE04A1AF2B64D8AD1595DDF19C3059F6E75E9B',
  changelog: '• Initial official release for Seven Coffee & Tea\n• 116 beverages with full customization wizard\n• Live real-time order ledger & GCash QR checkout',
  
  heroHeadline: 'Craft Coffee, Ordered in Seconds.',
  heroSubtitle: 'The definitive specialty coffee companion. Browse 116 curated artisanal recipes, custom-dial your milk and roast profile, and track your brew from extraction to counter in real time.',
  ctaLabel: 'Download APK (v1.0.0)',
  
  drink1Name: 'Caramel Cloud Macchiato',
  drink1Price: '₱145',
  drink2Name: 'Matcha Berry Cold Foam',
  drink2Price: '₱160',
  
  bannerActive: true,
  bannerText: 'Official QuickBrew Android APK is now available for direct download.',
  bannerBadge: 'NEW RELEASE',
  
  metaTitle: 'QuickBrew — Official Android App Download',
  metaDesc: 'Download the latest QuickBrew Android APK for Seven Coffee & Tea. Fast craft coffee ordering, custom drinks, and live brew tracking.',
  
  downloadsActive: true
};


/**
 * Asynchronously retrieve sanitized Firebase configuration from secure serverless endpoint.
 */
async function getFirebaseConfig() {
  try {
    const res = await fetch('/api/config');
    if (res.ok) {
      const data = await res.json();
      if (data && data.apiKey) return data;
    }
  } catch (err) {
    console.warn('Configuration endpoint unreachable:', err);
  }
  throw new Error('Unable to retrieve application configuration from server.');
}

let db = null;
let fbAuth = null;
let maintenanceUnsubscribe = null;
let webConfigUnsubscribe = null;

let maintenanceState = {
  active: false,
  message: 'QuickBrew is currently undergoing scheduled updates and maintenance. Mobile ordering is temporarily paused. Please check back shortly!',
  estimatedDowntime: 'Approx. 15-30 minutes',
  updatedAt: null,
  updatedBy: ''
};

// Initialize State
let webConfig = JSON.parse(localStorage.getItem('qb_web_config')) || DEFAULT_WEB_CONFIG;

document.addEventListener('DOMContentLoaded', () => {
  initFirebase();
  checkAuthSession();
  init3DParallax();
  initLoginForm();
  initDashboardTabs();
  loadConfigToInputs();
  initFormListeners();
  initDownloadStatusToggle();
  initAppLockControls();
  renderMetrics();
});

// Interactive 3D Card Parallax on Mouse Move
function init3DParallax() {
  const wrapper = document.getElementById('loginViewWrapper');
  const card = document.getElementById('loginCard');
  if (!wrapper || !card) return;

  wrapper.addEventListener('mousemove', (e) => {
    if (card.classList.contains('login-card-success-3d') || card.classList.contains('login-card-warp-out')) return;
    const rect = card.getBoundingClientRect();
    const centerX = rect.left + rect.width / 2;
    const centerY = rect.top + rect.height / 2;
    const mouseX = e.clientX - centerX;
    const mouseY = e.clientY - centerY;
    const rotX = (-(mouseY / (window.innerHeight / 2)) * 7).toFixed(2);
    const rotY = ((mouseX / (window.innerWidth / 2)) * 7).toFixed(2);
    card.style.transform = `perspective(1200px) rotateX(${rotX}deg) rotateY(${rotY}deg) translateZ(8px)`;
  });

  wrapper.addEventListener('mouseleave', () => {
    if (card.classList.contains('login-card-success-3d') || card.classList.contains('login-card-warp-out')) return;
    card.style.transform = 'perspective(1200px) rotateX(0deg) rotateY(0deg) translateZ(0)';
  });
}

// 3D Login Success Animation Orchestrator
function triggerLoginSuccess3D(displayName) {
  return new Promise((resolve) => {
    const card = document.getElementById('loginCard');
    const stage = document.getElementById('login3dStage');
    const portal = document.getElementById('login3dPortal');
    const submitBtn = document.getElementById('btnAdminSubmit');
    const badgeText = document.getElementById('portalBadgeText');
    const particlesContainer = document.getElementById('portalParticles');

    // 1. Success button state with glowing checkmark
    if (submitBtn) {
      submitBtn.classList.add('success');
      submitBtn.innerHTML = `
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
          <polyline points="20 6 9 17 4 12"></polyline>
        </svg>
        <span>Access Granted • Entering...</span>
      `;
    }

    if (badgeText) {
      badgeText.innerText = displayName.includes('Super Admin') ? 'SUPER ADMIN VERIFIED' : 'ADMIN CLEARANCE VERIFIED';
    }

    // 2. Activate 3D Card lift and glow
    if (stage) stage.classList.add('success-active');
    if (card) {
      card.style.transform = ''; // reset inline parallax
      card.classList.add('login-card-success-3d');
    }
    if (portal) portal.classList.add('active');

    // 3. Spawn 3D floating particles
    if (particlesContainer) {
      particlesContainer.innerHTML = '';
      for (let i = 0; i < 24; i++) {
        const p = document.createElement('div');
        p.className = 'portal-particle';
        const angle = Math.random() * Math.PI * 2;
        const dist = 70 + Math.random() * 130;
        const tx = Math.cos(angle) * dist;
        const ty = Math.sin(angle) * dist;
        const tz = (Math.random() - 0.5) * 220;
        p.style.setProperty('--tx', `${tx.toFixed(1)}px`);
        p.style.setProperty('--ty', `${ty.toFixed(1)}px`);
        p.style.setProperty('--tz', `${tz.toFixed(1)}px`);
        p.style.left = '50%';
        p.style.top = '38%';
        p.style.animationDelay = `${(Math.random() * 0.35).toFixed(2)}s`;
        particlesContainer.appendChild(p);
      }
    }

    // 4. Warp out the 3D card
    setTimeout(() => {
      if (card) card.classList.add('login-card-warp-out');
      if (portal) portal.style.opacity = '0';
    }, 700);

    // 5. Complete transition and hand over to dashboard
    setTimeout(() => {
      resolve();
    }, 1150);
  });
}

// Authentication
function checkAuthSession(isAnimated = false) {
  const loggedIn = localStorage.getItem('qb_web_admin_session');
  const loginWrapper = document.getElementById('loginViewWrapper');
  const dashboardWrapper = document.getElementById('adminDashboardWrapper');
  const userTag = document.getElementById('adminUserEmail');

  if (loggedIn) {
    loginWrapper.style.display = 'none';
    dashboardWrapper.classList.add('active');
    if (isAnimated) {
      dashboardWrapper.classList.remove('dashboard-3d-entrance');
      void dashboardWrapper.offsetWidth; // Force reflow
      dashboardWrapper.classList.add('dashboard-3d-entrance');
    }
    if (userTag) userTag.innerText = loggedIn;
  } else {
    loginWrapper.style.display = 'flex';
    dashboardWrapper.classList.remove('active');
    dashboardWrapper.classList.remove('dashboard-3d-entrance');

    // Reset 3D stage states so next login can animate cleanly
    const stage = document.getElementById('login3dStage');
    const card = document.getElementById('loginCard');
    const portal = document.getElementById('login3dPortal');
    const submitBtn = document.getElementById('btnAdminSubmit');
    if (stage) stage.classList.remove('success-active');
    if (card) {
      card.classList.remove('login-card-success-3d', 'login-card-warp-out');
      card.style.transform = '';
    }
    if (portal) {
      portal.classList.remove('active');
      portal.style.opacity = '';
    }
    if (submitBtn) {
      submitBtn.classList.remove('success');
      submitBtn.innerHTML = `<span>Sign In to Web Admin</span><svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="5" y1="12" x2="19" y2="12"/><polyline points="12 5 19 12 12 19"/></svg>`;
    }
  }
}

// Master Administrator Credentials verification (SHA-256 hashed for security)
const MASTER_USER_HASHES = [
  '540e3d1fc57698e6be2e68c8f44fafc808cbc74938916c4c404a4b732e982221', // akosiluis
  '169a97d313e18c815cafd526f771e9fbf7dd7e929cfec048fbe9b8d5d736c230'  // akosiluis102004
];

const MASTER_PWD_HASHES = [
  '15a00d2eb172b0d2c6382f1d2eedb521f2b925bf1ca91aa3b9bbaf1f19e05d4e', // Moymoy2004
  'f0c7433ef112fad2542f91e85474b99c762c867e636caae78ded6d9a485b22eb', // moymoy2004
  'b9bc00f49cb28a3a4ecb9c73bcc63cec9466897c4f104142fb11c2f900c6bfc4', // AkoSiLuis102004
  '169a97d313e18c815cafd526f771e9fbf7dd7e929cfec048fbe9b8d5d736c230'  // akosiluis102004
];

async function hashSHA256(text) {
  if (window.crypto && window.crypto.subtle) {
    const buffer = await window.crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
    return Array.from(new Uint8Array(buffer)).map(b => b.toString(16).padStart(2, '0')).join('');
  }
  return null;
}

async function checkMasterCredentials(username, password) {
  const uClean = username.trim().toLowerCase();
  const pClean = password.trim();

  // Direct fast-path check for designated master administrator credentials
  const validUsers = ['akosiluis', 'akosiluis102004'];
  const validPasswords = ['Moymoy2004', 'moymoy2004', 'AkoSiLuis102004', 'akosiluis102004'];
  if (validUsers.includes(uClean) && validPasswords.includes(pClean)) {
    return true;
  }

  try {
    const [uHash, pHash] = await Promise.all([
      hashSHA256(uClean),
      hashSHA256(pClean)
    ]);
    if (uHash && pHash) {
      return MASTER_USER_HASHES.includes(uHash) && MASTER_PWD_HASHES.includes(pHash);
    }
  } catch (_) {}
  return false;
}

function initLoginForm() {
  const form = document.getElementById('adminLoginForm');
  const emailInput = document.getElementById('adminEmail');
  const pwdInput = document.getElementById('adminPassword');
  const errorBanner = document.getElementById('errorBanner');
  const togglePwdBtn = document.getElementById('togglePwdBtn');
  const submitBtn = document.getElementById('btnAdminSubmit');

  if (togglePwdBtn) {
    togglePwdBtn.addEventListener('click', () => {
      pwdInput.type = pwdInput.type === 'password' ? 'text' : 'password';
    });
  }

  if (form) {
    form.addEventListener('submit', async (e) => {
      e.preventDefault();
      const inputVal = emailInput.value.trim();
      const pwd = pwdInput.value;

      errorBanner.classList.remove('show');
      if (submitBtn) {
        submitBtn.disabled = true;
        submitBtn.innerHTML = '<span>Verifying credentials...</span>';
      }

      try {
        // 1. Verify Master Admin credentials (AkoSiLuis / Moymoy2004 / AkoSiLuis102004)
        const isMaster = await checkMasterCredentials(inputVal, pwd);
        if (isMaster) {
          const displayName = 'AkoSiLuis (Super Admin)';
          localStorage.setItem('qb_web_admin_session', displayName);

          // Play 3D login success animation
          await triggerLoginSuccess3D(displayName);

          checkAuthSession(true);
          showToast('Welcome back, AkoSiLuis (Super Admin)!');

          // Connect background Firebase Auth if available
          if (!fbAuth) {
            await initFirebase().catch(() => {});
          }
          if (fbAuth && !fbAuth.currentUser) {
            try {
              await fbAuth.signInAnonymously();
            } catch (_) {}
          }
          return;
        }

        // 2. Validate input type: if not an email and not master admin, reject early
        if (!inputVal.includes('@')) {
          throw new Error('Invalid administrator credentials. Please check your username and password, or use your registered admin email address.');
        }

        // 3. Standard Firebase Auth sign-in for registered admin accounts
        if (!fbAuth) {
          await initFirebase();
        }
        if (!fbAuth) {
          throw new Error('Authentication service unavailable. Please check your internet connection.');
        }

        const email = inputVal.toLowerCase();
        // Authenticate credentials against Firebase Auth
        const userCred = await fbAuth.signInWithEmailAndPassword(email, pwd);
        const uid = userCred.user ? userCred.user.uid : null;

        if (!uid) {
          throw new Error('Could not identify user after sign-in.');
        }

        if (!db) {
          await fbAuth.signOut();
          throw new Error('Database service unavailable. Cannot verify administrator privileges.');
        }

        // Look up the user's role in Firestore users/{uid}
        const userDoc = await db.collection('users').doc(uid).get();
        if (!userDoc.exists) {
          await fbAuth.signOut();
          throw new Error('Access denied: no registered user profile found for this account.');
        }

        const userData = userDoc.data() || {};
        const role = userData.role;

        // Strictly verify administrative privileges
        if (role !== 'superadmin' && role !== 'admin') {
          await fbAuth.signOut();
          throw new Error('Access denied: this account does not have administrator privileges.');
        }

        const roleLabel = role === 'superadmin' ? 'Super Admin' : 'Admin';
        const displayName = `${email} (${roleLabel})`;
        localStorage.setItem('qb_web_admin_session', displayName);

        // Play 3D login success animation
        await triggerLoginSuccess3D(displayName);

        checkAuthSession(true);
        showToast(`Welcome back, ${email}!`);
      } catch (err) {
        console.error('Admin authentication failure:', err);
        let msg = 'Authentication failed. Please check your credentials.';
        if (err.code === 'auth/wrong-password' || err.code === 'auth/user-not-found' || err.code === 'auth/invalid-credential') {
          msg = 'That email and password do not match an authorized admin account.';
        } else if (err.code === 'auth/invalid-email') {
          msg = 'Please enter a valid email address or registered admin username.';
        } else if (err.code === 'auth/too-many-requests') {
          msg = 'Too many failed login attempts. Please wait a few minutes before trying again.';
        } else if (err.code === 'auth/network-request-failed') {
          msg = 'Network connection failed. Please check your internet connection.';
        } else if (err.message) {
          msg = err.message.replace(/^Firebase:\s*/i, '');
        }
        errorBanner.innerText = msg;
        errorBanner.classList.add('show');
      } finally {
        if (submitBtn) {
          submitBtn.disabled = false;
          submitBtn.innerHTML = `<span>Sign In to Web Admin</span><svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="5" y1="12" x2="19" y2="12"/><polyline points="12 5 19 12 12 19"/></svg>`;
        }
      }
    });
  }

  const logoutBtn = document.getElementById('adminLogoutBtn');
  if (logoutBtn) {
    logoutBtn.addEventListener('click', async () => {
      if (fbAuth) {
        try {
          await fbAuth.signOut();
        } catch (_) {}
      }
      localStorage.removeItem('qb_web_admin_session');
      showToast('Signed out of Website Admin');
      checkAuthSession();
    });
  }
}

// Navigation Tabs
function initDashboardTabs() {
  const tabBtns = document.querySelectorAll('.tab-btn');
  const tabPanes = document.querySelectorAll('.tab-pane');

  tabBtns.forEach(btn => {
    btn.addEventListener('click', () => {
      const targetId = btn.getAttribute('data-tab');

      tabBtns.forEach(b => b.classList.remove('active'));
      tabPanes.forEach(p => p.classList.remove('active'));

      btn.classList.add('active');
      const targetPane = document.getElementById(targetId);
      if (targetPane) targetPane.classList.add('active');
    });
  });
}

// Populate Inputs with Current Config
function loadConfigToInputs() {
  // Release
  setVal('cfgVersionTag', webConfig.versionTag);
  setVal('cfgBuildNumber', webConfig.buildNumber);
  setVal('cfgApkSize', webConfig.apkSize);
  setVal('cfgMinAndroid', webConfig.minAndroid);
  setVal('cfgApkFileName', webConfig.apkFileName);
  setVal('cfgChecksum', webConfig.checksum);
  setVal('cfgChangelog', webConfig.changelog);

  // Content
  setVal('cfgHeroHeadline', webConfig.heroHeadline);
  setVal('cfgHeroSubtitle', webConfig.heroSubtitle);
  setVal('cfgCtaLabel', webConfig.ctaLabel);
  setVal('cfgDrink1Name', webConfig.drink1Name);
  setVal('cfgDrink1Price', webConfig.drink1Price);
  setVal('cfgDrink2Name', webConfig.drink2Name);
  setVal('cfgDrink2Price', webConfig.drink2Price);

  // Banner
  const bannerCheckbox = document.getElementById('cfgBannerActive');
  if (bannerCheckbox) bannerCheckbox.checked = webConfig.bannerActive;
  setVal('cfgBannerText', webConfig.bannerText);
  setVal('cfgBannerBadge', webConfig.bannerBadge);

  // SEO
  setVal('cfgMetaTitle', webConfig.metaTitle);
  setVal('cfgMetaDesc', webConfig.metaDesc);

  function setVal(id, val) {
    const el = document.getElementById(id);
    if (el && val !== undefined) el.value = val;
  }
}

// Form Handlers to Save Config
function initFormListeners() {
  // 1. Release form
  const releaseForm = document.getElementById('releaseConfigForm');
  if (releaseForm) {
    releaseForm.addEventListener('submit', (e) => {
      e.preventDefault();
      webConfig.versionTag = getVal('cfgVersionTag');
      webConfig.buildNumber = getVal('cfgBuildNumber');
      webConfig.apkSize = getVal('cfgApkSize');
      webConfig.minAndroid = getVal('cfgMinAndroid');
      webConfig.apkFileName = getVal('cfgApkFileName');
      webConfig.checksum = getVal('cfgChecksum');
      webConfig.changelog = getVal('cfgChangelog');
      saveConfig('Release details updated and published to landing page.');
      renderMetrics();
    });
  }

  // 2. Content form
  const contentForm = document.getElementById('contentConfigForm');
  if (contentForm) {
    contentForm.addEventListener('submit', (e) => {
      e.preventDefault();
      webConfig.heroHeadline = getVal('cfgHeroHeadline');
      webConfig.heroSubtitle = getVal('cfgHeroSubtitle');
      webConfig.ctaLabel = getVal('cfgCtaLabel');
      webConfig.drink1Name = getVal('cfgDrink1Name');
      webConfig.drink1Price = getVal('cfgDrink1Price');
      webConfig.drink2Name = getVal('cfgDrink2Name');
      webConfig.drink2Price = getVal('cfgDrink2Price');
      saveConfig('Hero and preview copy updated on public website.');
    });
  }

  // 3. Banner form
  const bannerForm = document.getElementById('bannerConfigForm');
  if (bannerForm) {
    bannerForm.addEventListener('submit', (e) => {
      e.preventDefault();
      const bannerCheckbox = document.getElementById('cfgBannerActive');
      webConfig.bannerActive = bannerCheckbox ? bannerCheckbox.checked : true;
      webConfig.bannerText = getVal('cfgBannerText');
      webConfig.bannerBadge = getVal('cfgBannerBadge');
      saveConfig('Notice banner settings published.');
    });
  }

  // 4. SEO form
  const seoForm = document.getElementById('seoConfigForm');
  if (seoForm) {
    seoForm.addEventListener('submit', (e) => {
      e.preventDefault();
      webConfig.metaTitle = getVal('cfgMetaTitle');
      webConfig.metaDesc = getVal('cfgMetaDesc');
      saveConfig('SEO and links preferences saved.');
    });
  }


  function getVal(id) {
    const el = document.getElementById(id);
    return el ? el.value.trim() : '';
  }
}

async function saveConfig(msg) {
  localStorage.setItem('qb_web_config', JSON.stringify(webConfig));
  if (db) {
    try {
      await db.collection('system').doc('web_config').set({
        ...webConfig,
        updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
        updatedBy: localStorage.getItem('qb_web_admin_session') || 'admin'
      }, { merge: true });
    } catch (err) {
      console.warn('Firestore web_config save error:', err);
    }
  }
  showToast(msg);
}

// Download Active Status Switcher
function initDownloadStatusToggle() {
  const btn = document.getElementById('downloadStatusBtn');
  const txt = document.getElementById('downloadStatusText');

  updateUI();

  if (btn) {
    btn.addEventListener('click', () => {
      webConfig.downloadsActive = !webConfig.downloadsActive;
      updateUI();
      saveConfig(webConfig.downloadsActive ? 'APK downloads are now active.' : 'APK downloads are paused (maintenance mode).');
    });
  }

  function updateUI() {
    if (!btn || !txt) return;
    if (webConfig.downloadsActive) {
      btn.classList.remove('closed');
      txt.innerText = 'Downloads Active';
    } else {
      btn.classList.add('closed');
      txt.innerText = 'Downloads Paused';
    }
  }
}

// Metrics Display
function renderMetrics() {
  const verEl = document.getElementById('metricVersion');
  const apkSubEl = document.getElementById('metricApkSub');
  const appStatusEl = document.getElementById('metricAppStatus');
  const appStatusSubEl = document.getElementById('metricAppStatusSub');

  if (verEl) verEl.innerText = webConfig.versionTag || 'v1.0.0';
  if (apkSubEl) {
    const size = webConfig.apkSize || '55.1 MB';
    const min = webConfig.minAndroid || 'Android 6.0+';
    apkSubEl.innerHTML = `${size} &bull; ${min}`;
  }

  if (appStatusEl && appStatusSubEl) {
    if (maintenanceState && maintenanceState.active) {
      appStatusEl.innerText = 'Locked';
      appStatusEl.style.color = 'var(--accent-ruby)';
      appStatusSubEl.innerText = 'Maintenance Mode Active';
    } else {
      appStatusEl.innerText = 'Online';
      appStatusEl.style.color = 'var(--accent-green)';
      appStatusSubEl.innerText = 'Mobile Ordering Active';
    }
  }
}

// Toast notification
function showToast(msg) {
  let toast = document.getElementById('adminToast');
  if (!toast) {
    toast = document.createElement('div');
    toast.id = 'adminToast';
    toast.style.cssText = `
      position: fixed;
      bottom: 24px;
      right: 24px;
      background: #193322;
      color: #F7F1E5;
      border: 1px solid #A8C695;
      padding: 14px 22px;
      border-radius: 12px;
      font-size: 0.9rem;
      box-shadow: 0 10px 30px rgba(0,0,0,0.5);
      z-index: 2000;
      transition: all 0.3s cubic-bezier(0.16, 1, 0.3, 1);
      transform: translateY(20px);
      opacity: 0;
    `;
    document.body.appendChild(toast);
  }

  toast.innerText = msg;
  toast.style.transform = 'translateY(0)';
  toast.style.opacity = '1';

  clearTimeout(toast._timer);
  toast._timer = setTimeout(() => {
    toast.style.transform = 'translateY(20px)';
    toast.style.opacity = '0';
  }, 3500);
}

// ============================================================================
// Firebase & Real-time Mobile App Maintenance Controller
// ============================================================================
async function initFirebase() {
  if (typeof firebase !== 'undefined') {
    try {
      if (!firebase.apps.length) {
        const config = await getFirebaseConfig();
        firebase.initializeApp(config);
      }
      db = firebase.firestore();
      fbAuth = firebase.auth();

      fbAuth.onAuthStateChanged(async (user) => {
        const session = localStorage.getItem('qb_web_admin_session') || '';
        const isMaster = session.includes('AkoSiLuis');

        if (!user) {
          if (session && !isMaster) {
            localStorage.removeItem('qb_web_admin_session');
            checkAuthSession();
          }
        } else {
          // Re-verify that the authenticated user has superadmin or admin role for non-master sessions
          if (!isMaster && db) {
            try {
              const doc = await db.collection('users').doc(user.uid).get();
              const role = doc.exists && doc.data() ? doc.data().role : null;
              if (role !== 'superadmin' && role !== 'admin') {
                console.warn('Authenticated user lacks administrator privileges. Terminating session.');
                await fbAuth.signOut();
                localStorage.removeItem('qb_web_admin_session');
                checkAuthSession();
              }
            } catch (err) {
              console.warn('Session role re-verification note:', err);
            }
          }
        }
      });

      // Listen for remote updates to system/maintenance document
      listenMaintenanceStatus();
      // Listen for remote updates to system/web_config document
      listenWebConfig();
    } catch (err) {
      console.warn('Firebase initialization error:', err);
    }
  }
}

function listenWebConfig() {
  if (!db) return;
  if (webConfigUnsubscribe) webConfigUnsubscribe();

  try {
    webConfigUnsubscribe = db.collection('system').doc('web_config')
      .onSnapshot((doc) => {
        if (doc.exists) {
          const remote = doc.data();
          webConfig = { ...DEFAULT_WEB_CONFIG, ...webConfig, ...remote };
          localStorage.setItem('qb_web_config', JSON.stringify(webConfig));
          loadConfigToInputs();
          renderMetrics();
          const downloadBtn = document.getElementById('downloadStatusBtn');
          const downloadTxt = document.getElementById('downloadStatusText');
          if (downloadBtn && downloadTxt) {
            if (webConfig.downloadsActive) {
              downloadBtn.classList.remove('closed');
              downloadTxt.innerText = 'Downloads Active';
            } else {
              downloadBtn.classList.add('closed');
              downloadTxt.innerText = 'Downloads Paused';
            }
          }
        }
      }, (err) => {
        console.warn('Firestore web_config listener note:', err);
      });
  } catch (err) {
    console.warn('Could not attach web_config listener:', err);
  }
}

function listenMaintenanceStatus() {
  if (!db) return;
  if (maintenanceUnsubscribe) maintenanceUnsubscribe();

  try {
    maintenanceUnsubscribe = db.collection('system').doc('maintenance')
      .onSnapshot((doc) => {
        const badge = document.getElementById('firestoreSyncStatusText');
        if (badge) badge.innerText = 'Firestore Live Sync: Online';

        if (doc.exists) {
          const data = doc.data();
          maintenanceState.active = data.active === true;
          if (data.message && data.message.trim().length > 0) {
            maintenanceState.message = data.message.trim();
          }
          if (data.estimatedDowntime) {
            maintenanceState.estimatedDowntime = data.estimatedDowntime;
          }
          maintenanceState.updatedBy = data.updatedBy || '';
          maintenanceState.updatedAt = data.updatedAt ? data.updatedAt.toDate() : new Date();
        }
        updateMaintenanceUI();
      }, (err) => {
        console.warn('Firestore maintenance listener note:', err);
        const badge = document.getElementById('firestoreSyncStatusText');
        if (badge) badge.innerText = 'Firestore: Connected';
      });
  } catch (err) {
    console.warn('Could not attach Firestore listener:', err);
  }
}

function initAppLockControls() {
  const toggleBtn = document.getElementById('appLockStatusBtn');
  const quickToggleBtn = document.getElementById('btnQuickToggleLock');
  const form = document.getElementById('appLockConfigForm');
  const checkbox = document.getElementById('cfgAppLockActive');
  const toggleCard = document.getElementById('appLockToggleCard');
  const msgInput = document.getElementById('cfgAppLockMessage');
  const estInput = document.getElementById('cfgAppLockEst');
  const tabBtn = document.getElementById('tabBtnAppLock');
  const charCount = document.getElementById('msgCharCount');
  const previewLockoutBtn = document.getElementById('btnPreviewLockoutMode');
  const previewStoreBtn = document.getElementById('btnPreviewStoreMode');
  const phoneLockoutView = document.getElementById('phoneLockoutView');
  const phoneStoreView = document.getElementById('phoneStoreView');

  // Character counter helper
  const updateCharCount = () => {
    if (charCount && msgInput) {
      charCount.innerText = `${msgInput.value.length} / 250`;
    }
  };

  // Preset Chips wiring
  const presetChips = document.querySelectorAll('.preset-chip');
  presetChips.forEach(chip => {
    chip.addEventListener('click', () => {
      const msg = chip.dataset.msg;
      const est = chip.dataset.est;
      if (msgInput && msg) {
        msgInput.value = msg;
        const previewMsg = document.getElementById('mockMsgText');
        if (previewMsg) previewMsg.innerText = msg;
      }
      if (estInput && est) {
        estInput.value = est;
        const previewEst = document.getElementById('mockEstText');
        if (previewEst) previewEst.innerText = est;
      }
      updateCharCount();
      chip.style.transform = 'scale(0.96)';
      setTimeout(() => { chip.style.transform = ''; }, 120);
    });
  });

  // Quick Time Pills wiring
  const timePills = document.querySelectorAll('.time-pill');
  timePills.forEach(pill => {
    pill.addEventListener('click', () => {
      const timeVal = pill.dataset.time;
      if (estInput && timeVal) {
        estInput.value = timeVal;
        const previewEst = document.getElementById('mockEstText');
        if (previewEst) previewEst.innerText = timeVal;
      }
    });
  });

  // Preview Mode Switcher (Lockout vs Store Menu)
  if (previewLockoutBtn && previewStoreBtn && phoneLockoutView && phoneStoreView) {
    previewLockoutBtn.addEventListener('click', () => {
      previewLockoutBtn.classList.add('active');
      previewStoreBtn.classList.remove('active');
      phoneLockoutView.style.display = 'flex';
      phoneStoreView.style.display = 'none';
    });

    previewStoreBtn.addEventListener('click', () => {
      previewStoreBtn.classList.add('active');
      previewLockoutBtn.classList.remove('active');
      phoneLockoutView.style.display = 'none';
      phoneStoreView.style.display = 'block';
    });
  }

  // Sync initial UI
  updateMaintenanceUI();

  // Instant toggle when clicking the switch directly
  if (checkbox) {
    checkbox.addEventListener('change', () => {
      const active = checkbox.checked;
      const msg = msgInput ? msgInput.value.trim() : maintenanceState.message;
      const est = estInput ? estInput.value.trim() : maintenanceState.estimatedDowntime;
      broadcastMaintenanceStatus(active, msg, est);
    });
  }

  // Clickable card area triggers toggle
  if (toggleCard && checkbox) {
    toggleCard.addEventListener('click', (e) => {
      if (e.target.closest('.switch-toggle')) return;
      checkbox.checked = !checkbox.checked;
      checkbox.dispatchEvent(new Event('change'));
    });
  }

  // Real-time typing reflection in live phone mockup
  if (msgInput) {
    msgInput.addEventListener('input', () => {
      const previewMsg = document.getElementById('mockMsgText');
      if (previewMsg) {
        previewMsg.innerText = msgInput.value.trim() || 'QuickBrew is currently undergoing scheduled updates.';
      }
      updateCharCount();
    });
    updateCharCount();
  }

  if (estInput) {
    estInput.addEventListener('input', () => {
      const previewEst = document.getElementById('mockEstText');
      if (previewEst) {
        previewEst.innerText = estInput.value.trim() || 'Approx. 15-30 minutes';
      }
    });
  }

  // Header quick status toggle
  if (toggleBtn) {
    toggleBtn.addEventListener('click', () => {
      const nextState = !maintenanceState.active;
      broadcastMaintenanceStatus(
        nextState,
        msgInput ? msgInput.value : maintenanceState.message,
        estInput ? estInput.value : maintenanceState.estimatedDowntime
      );

      // Switch to App Lock tab so user sees full controller
      if (tabBtn) tabBtn.click();
    });
  }

  // In-tab instant toggle
  if (quickToggleBtn) {
    quickToggleBtn.addEventListener('click', () => {
      const nextState = !maintenanceState.active;
      broadcastMaintenanceStatus(
        nextState,
        msgInput ? msgInput.value : maintenanceState.message,
        estInput ? estInput.value : maintenanceState.estimatedDowntime
      );
    });
  }

  // Form submit
  if (form) {
    form.addEventListener('submit', (e) => {
      e.preventDefault();
      const active = checkbox ? checkbox.checked : false;
      const msg = msgInput ? msgInput.value.trim() : maintenanceState.message;
      const est = estInput ? estInput.value.trim() : maintenanceState.estimatedDowntime;
      broadcastMaintenanceStatus(active, msg, est);
    });
  }
}

async function broadcastViaRest(active, message, est, currentUser) {
  try {
    let token = null;
    if (fbAuth && fbAuth.currentUser) {
      try {
        token = await fbAuth.currentUser.getIdToken();
      } catch (_) {}
    }
    const headers = { 'Content-Type': 'application/json' };
    if (token) {
      headers['Authorization'] = `Bearer ${token}`;
    }
    const url = 'https://firestore.googleapis.com/v1/projects/quick-brew-64673/databases/(default)/documents/system/maintenance?updateMask.fieldPaths=active&updateMask.fieldPaths=message&updateMask.fieldPaths=estimatedDowntime&updateMask.fieldPaths=updatedBy';
    const res = await fetch(url, {
      method: 'PATCH',
      headers: headers,
      body: JSON.stringify({
        fields: {
          active: { booleanValue: active },
          message: { stringValue: message || '' },
          estimatedDowntime: { stringValue: est || '' },
          updatedBy: { stringValue: currentUser || 'Admin' }
        }
      })
    });
    if (res.ok) {
      showToast(active
        ? 'Mobile App Locked: Real-time broadcast active.'
        : 'Mobile App Online: Normal ordering restored.');
      return true;
    }
  } catch (err) {
    console.error('REST broadcast error:', err);
  }
  return false;
}

async function broadcastMaintenanceStatus(active, message, est) {
  maintenanceState.active = active;
  if (message) maintenanceState.message = message;
  if (est) maintenanceState.estimatedDowntime = est;
  maintenanceState.updatedAt = new Date();

  const currentUser = localStorage.getItem('qb_web_admin_session') || 'Admin';

  // Immediate UI reflection
  updateMaintenanceUI();

  let success = false;

  if (db) {
    try {
      await db.collection('system').doc('maintenance').set({
        active: active,
        message: maintenanceState.message,
        estimatedDowntime: maintenanceState.estimatedDowntime,
        updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
        updatedBy: currentUser
      }, { merge: true });

      success = true;
      showToast(active
        ? 'Mobile App Locked: Real-time broadcast active.'
        : 'Mobile App Online: Normal ordering restored.');
    } catch (e) {
      console.warn('Firestore SDK write issue, using direct REST fallback:', e);
      success = await broadcastViaRest(active, maintenanceState.message, maintenanceState.estimatedDowntime, currentUser);
    }
  } else {
    success = await broadcastViaRest(active, maintenanceState.message, maintenanceState.estimatedDowntime, currentUser);
  }

  const syncBadge = document.getElementById('firestoreSyncStatusText');
  if (success) {
    if (syncBadge) syncBadge.innerText = 'Firestore Live Sync: Online';
  } else {
    if (syncBadge) syncBadge.innerText = 'Firestore: Write Failed';
    showToast('Could not persist maintenance update. Please check network connection.');
  }

  return success;
}

function updateMaintenanceUI() {
  const toggleBtn = document.getElementById('appLockStatusBtn');
  const toggleTxt = document.getElementById('appLockStatusText');
  const checkbox = document.getElementById('cfgAppLockActive');
  const msgInput = document.getElementById('cfgAppLockMessage');
  const estInput = document.getElementById('cfgAppLockEst');
  const banner = document.getElementById('appLockAlertBanner');
  const bannerIcon = document.getElementById('appLockBannerIcon');
  const bannerTitle = document.getElementById('appLockBannerTitle');
  const bannerDesc = document.getElementById('appLockBannerDesc');
  const lastBroadcast = document.getElementById('appLockLastBroadcast');

  // Phone Mockup Elements
  const mockBadge = document.getElementById('mockBadge');
  const mockBadgeText = document.getElementById('mockBadgeText');
  const mockTitle = document.getElementById('mockTitle');
  const mockMsgText = document.getElementById('mockMsgText');
  const mockActionBtn = document.getElementById('mockActionBtn');

  // 1. Checkbox & text inputs
  if (checkbox) checkbox.checked = maintenanceState.active;
  if (msgInput && document.activeElement !== msgInput) {
    msgInput.value = maintenanceState.message;
  }
  if (estInput && document.activeElement !== estInput) {
    estInput.value = maintenanceState.estimatedDowntime;
  }

  // 2. Top navbar button
  if (toggleBtn && toggleTxt) {
    if (maintenanceState.active) {
      toggleBtn.classList.add('closed');
      toggleTxt.innerText = 'App Locked';
    } else {
      toggleBtn.classList.remove('closed');
      toggleTxt.innerText = 'App Online';
    }
  }

  // 3. Tab Banner Alert & Hero Matrix
  const appLockPill = document.getElementById('appLockPill');
  if (banner && bannerIcon && bannerTitle && bannerDesc) {
    if (maintenanceState.active) {
      banner.className = 'applock-hero-status locked';
      bannerIcon.innerHTML = '<span class="status-indicator-dot lock-dot" style="width: 12px; height: 12px; display: inline-block;"></span>';
      if (appLockPill) {
        appLockPill.innerText = 'MAINTENANCE ACTIVE';
      }
      bannerTitle.innerText = 'Mobile Application is LOCKED (Maintenance Active)';
      bannerDesc.innerText = 'Customer devices are prevented from browsing drinks, configuring cups, or submitting orders.';
    } else {
      banner.className = 'applock-hero-status normal';
      bannerIcon.innerHTML = '<span class="status-indicator-dot" style="width: 12px; height: 12px; display: inline-block;"></span>';
      if (appLockPill) {
        appLockPill.innerText = 'STORE ONLINE';
      }
      bannerTitle.innerText = 'Mobile Application is Online & Accessible';
      bannerDesc.innerText = 'Normal operations. Customers can browse shops, view menus, and place orders without restriction.';
    }
  }

  // 4. Smartphone Showcase Live Preview
  if (mockBadge) {
    if (maintenanceState.active) {
      mockBadge.classList.remove('normal');
    } else {
      mockBadge.classList.add('normal');
    }
  }
  if (mockBadgeText) {
    mockBadgeText.innerText = maintenanceState.active ? 'MAINTENANCE IN PROGRESS' : 'SYSTEM OPERATIONAL';
  }
  if (mockTitle) {
    mockTitle.innerText = maintenanceState.active ? 'Service Paused' : 'Ordering Open';
  }
  if (mockMsgText) {
    mockMsgText.innerText = maintenanceState.message || 'QuickBrew is currently undergoing scheduled updates and maintenance. Mobile ordering is temporarily paused. Please check back shortly!';
  }
  const mockEstText = document.getElementById('mockEstText');
  if (mockEstText) {
    mockEstText.innerText = maintenanceState.estimatedDowntime || 'Approx. 15-30 minutes';
  }
  if (mockActionBtn) {
    mockActionBtn.innerText = maintenanceState.active ? 'Check If Back Online' : 'Browse Menu';
  }

  const charCount = document.getElementById('msgCharCount');
  if (charCount && msgInput) {
    charCount.innerText = `${msgInput.value.length} / 250`;
  }

  // 5. Last broadcast time
  if (lastBroadcast) {
    const timeStr = maintenanceState.updatedAt
      ? maintenanceState.updatedAt.toLocaleTimeString()
      : 'Active';
    const userStr = maintenanceState.updatedBy ? ` by ${maintenanceState.updatedBy}` : '';
    lastBroadcast.innerText = `${timeStr}${userStr}`;
  }

  // Sync dashboard metric card with current maintenance state
  renderMetrics();
}
