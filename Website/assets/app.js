/**
 * QuickBrew Download Portal - Interactive Scripts & Real-time Live CMS Client
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
  
  metaTitle: 'QuickBrew — Official Android Release',
  metaDesc: 'Download the official QuickBrew Android release for Seven Coffee & Tea. Precision coffee ordering, customizable brews, and live extraction tracking.',
  
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

let currentWebConfig = JSON.parse(localStorage.getItem('qb_web_config')) || DEFAULT_WEB_CONFIG;
let qrCodeInstance = null;
let db = null;

document.addEventListener('DOMContentLoaded', () => {
  applyCmsConfig(currentWebConfig);
  initFirebaseSync();
  recordVisitor();
  initDownloadButtons();
  initCopyChecksum();
  generateQRCode();
  initSmoothScroll();
  initMobileNavigation();
  initMobileStickyBar();
  detectMobileDevice();
});

/**
 * Hydrate and update dynamic website content from config
 */
function applyCmsConfig(cfg) {
  if (!cfg) return;

  try {
    // Announcement banner
    const banner = document.getElementById('announcementBar');
    const bText = document.getElementById('announcementText');
    const bBadge = document.getElementById('announcementBadge');
    if (banner) {
      if (cfg.bannerActive === false) {
        banner.classList.remove('show');
      } else {
        banner.classList.add('show');
        if (bText && cfg.bannerText) bText.innerText = cfg.bannerText;
        if (bBadge && cfg.bannerBadge) bBadge.innerText = cfg.bannerBadge;
      }
    }

    // Hero section
    const headline = document.getElementById('mainHeroHeadline');
    if (headline && cfg.heroHeadline) headline.innerText = cfg.heroHeadline;

    const subtitle = document.getElementById('mainHeroSubtitle');
    if (subtitle && cfg.heroSubtitle) subtitle.innerText = cfg.heroSubtitle;

    const versionTag = document.getElementById('heroVersionTag');
    if (versionTag && cfg.versionTag) versionTag.innerText = `Official Release • ${cfg.versionTag}`;

    const drawerVer = document.getElementById('mobileDrawerVersion');
    if (drawerVer && cfg.versionTag) drawerVer.innerText = `Official Release • ${cfg.versionTag}`;

    const ctaLabel = document.getElementById('heroCtaLabel');
    if (ctaLabel && cfg.ctaLabel) ctaLabel.innerText = cfg.ctaLabel;

    const apkSize = document.getElementById('heroApkSize');
    if (apkSize && cfg.apkSize) apkSize.innerText = `APK Size: ${cfg.apkSize}`;

    const minAndroid = document.getElementById('heroMinAndroid');
    if (minAndroid && cfg.minAndroid) minAndroid.innerText = cfg.minAndroid;

    const checksumEl = document.getElementById('checksumHash');
    if (checksumEl && cfg.checksum) checksumEl.innerText = cfg.checksum;

    // Phone Mockup Drinks
    const d1Title = document.getElementById('mockupDrink1Title');
    const d1Price = document.getElementById('mockupDrink1Price');
    if (d1Title && cfg.drink1Name) d1Title.innerText = cfg.drink1Name;
    if (d1Price && cfg.drink1Price) d1Price.innerText = cfg.drink1Price;

    const d2Title = document.getElementById('mockupDrink2Title');
    const d2Price = document.getElementById('mockupDrink2Price');
    if (d2Title && cfg.drink2Name) d2Title.innerText = cfg.drink2Name;
    if (d2Price && cfg.drink2Price) d2Price.innerText = cfg.drink2Price;

    // Browser title & meta
    if (cfg.metaTitle) document.title = cfg.metaTitle;

    // Download links href & download attributes
    const fileName = cfg.apkFileName || 'quickbrew-release.apk';
    document.querySelectorAll('.btn-download').forEach(btn => {
      btn.setAttribute('href', fileName);
      btn.setAttribute('download', fileName);
      if (cfg.downloadsActive === false) {
        btn.style.opacity = '0.6';
        btn.setAttribute('title', 'Downloads temporarily paused for scheduled maintenance');
      } else {
        btn.style.opacity = '1';
        btn.removeAttribute('title');
      }
    });
  } catch (e) {
    console.warn('CMS config hydration note:', e);
  }
}

/**
 * Initialize real-time sync with Firestore system/web_config
 */
async function initFirebaseSync() {
  if (typeof firebase !== 'undefined') {
    try {
      if (!firebase.apps.length) {
        const config = await getFirebaseConfig();
        firebase.initializeApp(config);
      }
      db = firebase.firestore();

      db.collection('system').doc('web_config')
        .onSnapshot((doc) => {
          if (doc.exists) {
            const remoteData = doc.data();
            const prevFileName = currentWebConfig.apkFileName;
            currentWebConfig = { ...DEFAULT_WEB_CONFIG, ...currentWebConfig, ...remoteData };
            localStorage.setItem('qb_web_config', JSON.stringify(currentWebConfig));
            applyCmsConfig(currentWebConfig);

            if (prevFileName !== currentWebConfig.apkFileName) {
              generateQRCode();
            }
          }
        }, (err) => {
          console.warn('Firestore web_config live sync note:', err);
        });
    } catch (err) {
      console.warn('Firebase init error in landing page:', err);
    }
  }
}

/**
 * Track Unique Page Visits for Admin Dashboard
 */
function recordVisitor() {
  const visits = Number(localStorage.getItem('qb_visit_count') || 528);
  if (!sessionStorage.getItem('qb_visited_session')) {
    sessionStorage.setItem('qb_visited_session', 'true');
    localStorage.setItem('qb_visit_count', visits + 1);
  }
}

/**
 * Handle APK Download actions with interactive feedback & Analytics increment
 */
function initDownloadButtons() {
  const downloadBtns = document.querySelectorAll('.btn-download');
  
  downloadBtns.forEach(btn => {
    btn.addEventListener('click', (e) => {
      if (currentWebConfig && currentWebConfig.downloadsActive === false) {
        e.preventDefault();
        showToast('Downloads are temporarily paused for scheduled maintenance. Please check back shortly.');
        return;
      }

      // Increment live download count for admin analytics
      const current = Number(localStorage.getItem('qb_download_count') || 142);
      localStorage.setItem('qb_download_count', current + 1);

      showToast('Preparing QuickBrew APK package...');
      
      setTimeout(() => {
        showToast('Download initiated. Check your notification bar.');
      }, 1200);
    });
  });
}

/**
 * Copy Checksum to Clipboard
 */
function initCopyChecksum() {
  const copyBtn = document.getElementById('copyChecksumBtn');
  const hashEl = document.getElementById('checksumHash');
  
  if (!copyBtn || !hashEl) return;
  
  copyBtn.addEventListener('click', () => {
    const textToCopy = hashEl.innerText.trim();
    navigator.clipboard.writeText(textToCopy).then(() => {
      showToast('SHA-256 checksum copied to clipboard.');
      const originalText = copyBtn.innerText;
      copyBtn.innerText = 'COPIED!';
      setTimeout(() => {
        copyBtn.innerText = originalText;
      }, 2000);
    }).catch(() => {
      showToast('Could not copy automatically. Please select text.');
    });
  });
}

/**
 * Show Toast Notification
 */
function showToast(message) {
  let toast = document.querySelector('.toast-notice');
  if (!toast) {
    toast = document.createElement('div');
    toast.className = 'toast-notice';
    document.body.appendChild(toast);
  }
  
  toast.textContent = message;
  toast.classList.add('show');
  
  clearTimeout(toast._timer);
  toast._timer = setTimeout(() => {
    toast.classList.remove('show');
  }, 3500);
}

/**
 * Genuine QR Code Generator for mobile camera scanning
 * Points to the download link
 */
function generateQRCode() {
  const container = document.getElementById('qrCodeContainer');
  if (!container) return;

  const fileName = currentWebConfig.apkFileName || 'quickbrew-release.apk';
  const downloadUrl = new URL(fileName, window.location.href).href;

  container.innerHTML = '';
  if (typeof QRCode !== 'undefined') {
    qrCodeInstance = new QRCode(container, {
      text: downloadUrl,
      width: 140,
      height: 140,
      colorDark: '#102216',
      colorLight: '#ffffff',
      correctLevel: QRCode.CorrectLevel.M
    });
  } else {
    // Fallback if library is still downloading or blocked
    container.innerHTML = `
      <div style="width:140px;height:140px;display:flex;flex-direction:column;align-items:center;justify-content:center;color:#102216;font-size:0.75rem;text-align:center;padding:8px;font-family:inherit;">
        <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style="margin-bottom:6px;"><rect x="3" y="3" width="18" height="18" rx="2"/><path d="M7 7h.01M7 17h.01M17 7h.01M17 17h.01"/></svg>
        <span>Direct APK Link</span>
      </div>
    `;
  }
}

/**
 * Smooth scrolling helper
 */
function initSmoothScroll() {
  document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', function(e) {
      const targetId = this.getAttribute('href');
      if (targetId === '#' || targetId === '') return;
      const target = document.querySelector(targetId);
      if (target) {
        e.preventDefault();
        target.scrollIntoView({
          behavior: 'smooth',
          block: 'start'
        });
      }
    });
  });
}

/**
 * Mobile Navigation Drawer Toggle and Gestures
 */
function initMobileNavigation() {
  const toggleBtn = document.getElementById('mobileNavToggle');
  const drawer = document.getElementById('mobileDrawer');
  const backdrop = document.getElementById('mobileDrawerBackdrop');
  const closeBtn = document.getElementById('mobileDrawerClose');

  if (!toggleBtn || !drawer || !backdrop) return;

  function openDrawer() {
    drawer.classList.add('open');
    backdrop.classList.add('open');
    toggleBtn.classList.add('active');
    toggleBtn.setAttribute('aria-expanded', 'true');
    document.body.classList.add('menu-locked');
  }

  function closeDrawer() {
    drawer.classList.remove('open');
    backdrop.classList.remove('open');
    toggleBtn.classList.remove('active');
    toggleBtn.setAttribute('aria-expanded', 'false');
    document.body.classList.remove('menu-locked');
  }

  toggleBtn.addEventListener('click', (e) => {
    e.stopPropagation();
    if (drawer.classList.contains('open')) {
      closeDrawer();
    } else {
      openDrawer();
    }
  });

  if (closeBtn) {
    closeBtn.addEventListener('click', closeDrawer);
  }

  backdrop.addEventListener('click', closeDrawer);

  // Close when pressing Escape key
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && drawer.classList.contains('open')) {
      closeDrawer();
    }
  });

  // Auto-close when clicking any link inside the mobile drawer
  drawer.querySelectorAll('a').forEach(link => {
    link.addEventListener('click', () => {
      closeDrawer();
    });
  });
}

/**
 * Mobile Sticky Bottom Download Bar (reveals when scrolled past hero on phones)
 */
function initMobileStickyBar() {
  const bar = document.getElementById('mobileBottomBar');
  if (!bar) return;

  let ticking = false;

  window.addEventListener('scroll', () => {
    if (!ticking) {
      window.requestAnimationFrame(() => {
        if (window.innerWidth <= 768) {
          // Show after scrolling 320px down (past hero headline)
          if (window.scrollY > 320) {
            bar.classList.add('visible');
          } else {
            bar.classList.remove('visible');
          }
        } else {
          bar.classList.remove('visible');
        }
        ticking = false;
      });
      ticking = true;
    }
  }, { passive: true });
}

/**
 * Detect Mobile Device & Adapt QR Section
 */
function detectMobileDevice() {
  const isMobile = window.innerWidth <= 768 || /Android|iPhone|iPad|iPod|Mobile/i.test(navigator.userAgent);
  const banner = document.getElementById('qrMobileBanner');
  const title = document.getElementById('qrTitleText');
  const desc = document.getElementById('qrDescText');

  if (isMobile) {
    if (banner) banner.style.display = 'flex';
    if (title) title.innerText = 'Scan from Another Device';
    if (desc) desc.innerText = 'Or show this QR code to a friend so they can install QuickBrew directly on their phone.';
  }
}
