(async function () {
  // Domain allow-list — SHA-256 hashes of hostname (www. stripped).
  // To add a domain: echo -n 'example.com' | shasum -a 256
  const ALLOWED_HASHES = new Set([
    '91dcc18fc7d646eb1537a364d7f7991e1254c63d9d3ccb75b1c388cd528526b2',
    '12ca17b49af2289436f303e0166030a21e525d266e209267433801a8fd4071a0',
    '49960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d9763',
  ]);

  try {
    const host = window.location.hostname.replace(/^www\./, '');
    const buf  = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(host));
    const hex  = Array.from(new Uint8Array(buf)).map(b => b.toString(16).padStart(2, '0')).join('');
    if (!ALLOWED_HASHES.has(hex)) return;
  } catch {
    return;
  }

  const MIN_AREA = 8000;

  let overlay    = null;
  let currentImg = null;
  let hideTimer  = null;
  let cachedTargetDir = null;
  let dupeState  = null; // { src, expires } — armed after first click on a dupe

  // Returns false if the extension was reloaded and this content script is orphaned.
  function runtimeAlive() {
    try { return !!chrome.runtime?.id; } catch { return false; }
  }

  function sendMsg(msg, cb) {
    if (!runtimeAlive()) return;
    try { chrome.runtime.sendMessage(msg, cb); } catch { /* orphaned */ }
  }

  function refreshTargetDir() {
    sendMsg({ action: 'get_target_dir' }, (response) => {
      if (response?.dir) cachedTargetDir = response.dir;
    });
  }
  refreshTargetDir();

  function truncatePath(path, maxLen = 48) {
    if (!path || path.length <= maxLen) return path;
    const parts = path.replace(/\/$/, '').split('/').filter(Boolean);
    const filename = parts[parts.length - 1];
    const dir      = parts.length > 1 ? parts[parts.length - 2] : null;
    // Always show at least dir/filename even if that alone exceeds maxLen
    let suffix = dir ? dir + '/' + filename : filename;
    // Prepend additional ancestors while they fit
    for (let i = parts.length - 3; i >= 0; i--) {
      const candidate = parts[i] + '/' + suffix;
      if (candidate.length > maxLen - 2) break;
      suffix = candidate;
    }
    return '…/' + suffix;
  }

  function btnTitle() {
    return cachedTargetDir
      ? `Download to ${truncatePath(cachedTargetDir)}`
      : 'Download image (no folder set — click extension icon to choose)';
  }

  function createOverlay() {
    const div = document.createElement('div');
    div.id = '__img_dl_overlay__';
    div.innerHTML = `<div class="img-dl-btn" title="${btnTitle()}">⬇</div>`;
    document.body.appendChild(div);

    const btn = div.querySelector('.img-dl-btn');

    btn.addEventListener('mouseenter', () => clearTimeout(hideTimer));
    btn.addEventListener('mouseleave', scheduleHide);

    btn.addEventListener('click', (e) => {
      e.stopPropagation();
      e.preventDefault();
      const img = currentImg;
      if (!img) return;

      if (!runtimeAlive()) {
        showToast(img, '✗ Extension was reloaded — please refresh this page');
        return;
      }

      const src = img.currentSrc || img.src;
      if (!src || src.startsWith('data:')) {
        showToast(img, '✗ No downloadable URL found');
        return;
      }

      // Second click within the dupe window → open the file picker
      const allowDupe = !!(dupeState && dupeState.src === src && Date.now() < dupeState.expires);
      if (allowDupe) dupeState = null;

      showState(btn, '…', null);
      const resetTimer = setTimeout(() => {
        showToast(img, '✗ Timed out — see last error in the extension popup');
        showState(btn, '✗', false);
      }, 70000);

      sendMsg({ action: 'download_image', src, allowDupe }, (response) => {
        clearTimeout(resetTimer);
        const lastErr = runtimeAlive() ? chrome.runtime.lastError : null;

        if (response?.dupe) {
          // First encounter with a dupe — arm the second-click window
          dupeState = { src, expires: Date.now() + 5000 };
          showToast(img, '⚠ Already exists — click ⬇ again to choose a location');
          btn.textContent = '⬇';
        } else if (lastErr || !response?.success) {
          const err = response?.error || lastErr?.message || 'Download failed';
          showToast(img, `✗ ${err}`);
          showState(btn, '✗', false);
        } else {
          const savedTo = response.destPath;
          showToast(img, savedTo ? `✓ Saved to ${truncatePath(savedTo)}` : '✓ Saved');
          showState(btn, '✓', true);
        }
        img.focus({ preventScroll: true });
      });
    });

    return div;
  }

  function showState(btn, symbol, success) {
    btn.textContent = symbol;
    if (success === null) return;
    setTimeout(() => { btn.textContent = '⬇'; }, 1800);
  }

  let toast      = null;
  let toastTimer = null;

  function getToast() {
    if (!toast || !document.body.contains(toast)) {
      toast = document.createElement('div');
      toast.id = '__img_dl_toast__';
      document.body.appendChild(toast);
    }
    return toast;
  }

  function showToast(img, message) {
    const t = getToast();
    const rect = img.getBoundingClientRect();
    t.style.left      = `${rect.left + window.scrollX + rect.width  / 2}px`;
    t.style.top       = `${rect.top  + window.scrollY + rect.height / 2}px`;
    t.style.transform = 'translate(-50%, -50%)';
    t.textContent = message;
    t.style.opacity = '1';
    t.style.display = 'flex';
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => {
      t.style.opacity = '0';
      setTimeout(() => { t.style.display = 'none'; }, 260);
    }, 3000);
  }

  function getOverlay() {
    if (!overlay || !document.body.contains(overlay)) {
      overlay = createOverlay();
    }
    return overlay;
  }

  function positionOverlay(img) {
    const rect = img.getBoundingClientRect();
    const ov = getOverlay();
    ov.style.left = `${rect.right  + window.scrollX - 44}px`;
    ov.style.top  = `${rect.bottom + window.scrollY - 44}px`;
    ov.querySelector('.img-dl-btn').title = btnTitle();
    ov.style.display = 'block';
  }

  function scheduleHide() {
    hideTimer = setTimeout(() => {
      if (overlay) overlay.style.display = 'none';
      currentImg = null;
    }, 220);
  }

  function isLargeEnough(img) {
    const w = img.naturalWidth  || img.getBoundingClientRect().width;
    const h = img.naturalHeight || img.getBoundingClientRect().height;
    return w * h >= MIN_AREA;
  }

  document.addEventListener('mouseover', (e) => {
    let img = e.target.closest('img');
    if (!img) {
      const under = document.elementsFromPoint(e.clientX, e.clientY);
      img = under.find(el => el.tagName === 'IMG') || null;
    }
    if (!img || !isLargeEnough(img)) return;
    clearTimeout(hideTimer);
    currentImg = img;
    positionOverlay(img);
  });

  document.addEventListener('mouseout', (e) => {
    if (e.target === currentImg) scheduleHide();
  });

  window.addEventListener('scroll', () => {
    if (currentImg && overlay?.style.display !== 'none') {
      positionOverlay(currentImg);
    }
  }, { passive: true });
})();
