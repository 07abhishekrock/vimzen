'use strict';
/* vimzen poc — modal input + bottom bar experiments.
 * Single global key handler + per-frame hooks. No deps, no build. */

// ---------------- dom ----------------
const $ = (id) => document.getElementById(id);
const els = {
  frames: $('frames'), overlay: $('overlay'), bar: $('bar'),
  badge: $('badge'), pending: $('pending'), tabpos: $('tabpos'),
  media: $('media'), addr: $('addr'), flash: $('flash'),
  findstate: $('findstate'), loadstate: $('loadstate'), clock: $('clock'),
  ebBottom: $('editbar-bottom'), ebPrompt: $('eb-prompt'),
  ebInput: $('eb-input'), ebHint: $('eb-hint'),
  ebTop: $('editbar-top'), ebTopPrompt: $('editbar-top-prompt'),
  ebTopInput: $('editbar-top-input'), ebTopHint: $('editbar-top-hint'),
  suggest: $('suggest'), tabov: $('taboverlay'),
  help: $('help'), settings: $('settings'), debug: $('debug'), debuglog: $('debuglog'),
};

function shorten(s, n) {
  return s.length <= n ? s : s.slice(0, Math.ceil(n / 2)) + '…' + s.slice(-Math.floor(n / 2));
}

// ---------------- debug log ----------------
const DEBUG = [];
function log(msg) {
  const t = new Date().toTimeString().slice(0, 8);
  DEBUG.push(`[${t}] ${msg}`);
  if (DEBUG.length > 200) DEBUG.shift();
  if (!els.debug.classList.contains('hidden')) renderDebug();
}
function renderDebug() {
  els.debuglog.textContent = DEBUG.slice(-60).join('\n');
  els.debuglog.scrollTop = els.debuglog.scrollHeight;
}

// ---------------- flash ----------------
let flashTimer = null;
function flash(msg, ms = 1800) {
  els.flash.textContent = msg;
  clearTimeout(flashTimer);
  flashTimer = setTimeout(() => { els.flash.textContent = ''; }, ms);
}

// ---------------- settings (experiments) ----------------
const DEFAULTS = {
  urlPlacement: 'hybrid',   // statusline | hybrid | hidden
  editPosition: 'bottom',   // bottom | top
  prefill: 'select',        // select | end | empty
  engine: 'ddg',            // ddg | google | bing
  tint: true, accent: true, fadeBadge: false, showOverlay: false,
};
const settings = { ...DEFAULTS };
try {
  const raw = JSON.parse(localStorage.getItem('vimzen-poc') || '{}');
  for (const k of Object.keys(DEFAULTS)) if (k in raw) settings[k] = raw[k];
} catch { /* corrupted storage -> defaults */ }
function saveSettings() {
  localStorage.setItem('vimzen-poc', JSON.stringify(settings));
}

// ---------------- tabs ----------------
const SCROLL_PX = 60;
const BLOCKED_HOSTS = [
  'google.com', 'github.com', 'x.com', 'twitter.com', 'facebook.com',
  'instagram.com', 'linkedin.com', 'netflix.com', 'chatgpt.com', 'chat.openai.com',
];
const SEARCH_URLS = {
  ddg: 'https://duckduckgo.com/?q=',
  google: 'https://www.google.com/search?q=',
  bing: 'https://www.bing.com/search?q=',
};

const tabs = [
  { url: 'sites/scroll.html', title: '', status: 'loading', media: false, mediaSince: 0, sameOrigin: true, frame: null, timers: [], faded: false },
  { url: 'sites/form.html',   title: '', status: 'loading', media: false, mediaSince: 0, sameOrigin: true, frame: null, timers: [], faded: false },
  { url: 'sites/media.html',  title: '', status: 'loading', media: false, mediaSince: 0, sameOrigin: true, frame: null, timers: [], faded: false },
];
let active = 0;
const tab = () => tabs[active];

function isBlockedHost(url) {
  try {
    const h = new URL(url, location.href).hostname;
    return BLOCKED_HOSTS.some((b) => h === b || h.endsWith('.' + b));
  } catch { return false; }
}

function wireFrame(i) {
  const t = tabs[i];
  const f = document.createElement('iframe');
  f.src = t.url;
  t.frame = f;
  els.frames.appendChild(f);
  startLoadTimers(t);
  f.addEventListener('load', () => onFrameLoad(i));
  f.addEventListener('error', () => {
    t.status = 'error';
    log(`tab ${i + 1}: error event (rare — most iframe failures are silent)`);
    render();
  });
}

function startLoadTimers(t) {
  t.timers.forEach(clearTimeout);
  t.timers = [
    setTimeout(() => {
      if (t.status === 'loading') { t.status = 'slow'; log('load >3s -> slow'); render(); }
    }, 3000),
    setTimeout(() => {
      if (t.status === 'loading' || t.status === 'slow') {
        t.status = 'error'; log('load >20s -> error (timeout)'); render();
      }
    }, 20000),
  ];
}

function onFrameLoad(i) {
  const t = tabs[i];
  t.timers.forEach(clearTimeout);
  t.timers = [];
  if (t.status !== 'blocked') t.status = 'ok';
  t.faded = false;
  setTimeout(() => { if (t.status === 'ok') { t.faded = true; render(); } }, 2000);
  try {
    const d = t.frame.contentDocument;
    if (d && d.URL && !d.URL.startsWith('about:')) {
      t.sameOrigin = true;
      if (t.url !== d.URL) log(`tab ${i + 1} in-frame nav -> ${shorten(d.URL, 60)}`);
      t.url = d.URL;
      t.title = d.title || '';
      hookFrameDoc(t, d);
    }
  } catch {
    t.sameOrigin = false;
    try { t.title = new URL(t.url).hostname; } catch { t.title = ''; }
    log(`tab ${i + 1} is cross-origin — no scroll/find/esc inside (needs engine hooks)`);
  }
  log(`tab ${i + 1} load event -> ${t.status}`);
  render();
  renderTabOverlay();
}

// Same-origin hooks: Esc forwarding + auto-insert. This is what R1/R10
// (per-tab JS injection + editable-focus detection) will give us for real.
function hookFrameDoc(t, d) {
  // Inject mode-aware cursor styles into same-origin frames
  try {
    if (!d.getElementById('vimzen-cursor-style')) {
      const st = d.createElement('style');
      st.id = 'vimzen-cursor-style';
      st.textContent = `
        body.mode-insert { cursor: text !important; }
      `;
      d.head.appendChild(st);
    }
  } catch { /* cross-origin */ }

  d.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' || (e.ctrlKey && e.key === '[')) {
      e.preventDefault();
      toNormal('esc from page');
    }
  }, true);
  d.addEventListener('focusin', (e) => {
    const tgt = e.target;
    if (mode === 'NORMAL' && tgt.closest && tgt.closest('input,textarea,select,[contenteditable]')) {
      toInsert('auto-insert: field focused');
    }
  });
}

function navigate(t, url) {
  clearFind();
  const finalUrl = new URL(url, location.href).href;
  t.url = finalUrl;
  t.title = '';
  t.faded = false;
  t.status = isBlockedHost(finalUrl) ? 'blocked' : 'loading';
  if (t.status === 'blocked') {
    log(`blocked host (X-Frame-Options likely): ${new URL(finalUrl).hostname}`);
  }
  startLoadTimers(t);
  t.frame.src = finalUrl;
  log(`navigate -> ${shorten(finalUrl, 60)} [${t.status}]`);
  render();
}

function reloadTab() {
  const t = tab();
  t.status = 'loading';
  t.faded = false;
  startLoadTimers(t);
  try { t.frame.contentWindow.location.reload(); }
  catch { t.frame.src = t.url; } // cross-origin: Location.reload is blocked
  log('reload');
  render();
}

function switchTab(i) {
  const idx = Math.max(0, Math.min(tabs.length - 1, i));
  if (idx === active) return;
  active = idx;
  tabs.forEach((t, j) => t.frame.classList.toggle('active', j === active));
  if (mode === 'INSERT' && !tab().sameOrigin) toNormal('left cross-origin tab');
  log(`tab ${active + 1}/${tabs.length}`);
  render();
  renderTabOverlay();
}
function stepTab(d) { switchTab((active + d + tabs.length) % tabs.length); }

// ---------------- page interaction helpers (same-origin only) ----------------
function scrollActive(dx, dy) {
  try { tab().frame.contentWindow.scrollBy({ left: dx, top: dy, behavior: 'instant' }); }
  catch { flash('scroll unavailable (cross-origin)'); log('scroll blocked — needs JS injection (R1)'); }
}
function scrollToPos(where) {
  try {
    const w = tab().frame.contentWindow;
    w.scrollTo(0, where === 'top' ? 0 : w.document.documentElement.scrollHeight);
  } catch { flash('scroll unavailable (cross-origin)'); }
}
function pageAmount(frac) {
  try { return Math.max(40, tab().frame.contentWindow.innerHeight * frac); }
  catch { return 0; }
}
function historyNav(dir) {
  try { tab().frame.contentWindow.history.go(dir); log(`history ${dir > 0 ? 'forward' : 'back'}`); }
  catch { flash('history unavailable'); }
}
function findActive(q, backwards = false) {
  try {
    const found = tab().frame.contentWindow.find(q, false, backwards, true);
    if (!found) flash(`not found: ${q}`);
    return found;
  } catch { flash('find unavailable (cross-origin)'); return false; }
}
function clearFind() {
  lastFind = '';
  findTotal = null;
  findIdx = 0;
  try { tab().frame.contentWindow.getSelection().removeAllRanges(); } catch { /* cross-origin */ }
}
function countMatches(q) {
  if (!q) return 0;
  try {
    const d = tab().frame.contentDocument;
    const walker = d.createTreeWalker(d.body, NodeFilter.SHOW_TEXT);
    const ql = q.toLowerCase();
    let n = 0, node;
    while ((node = walker.nextNode())) {
      const s = node.nodeValue.toLowerCase();
      let i = 0;
      while ((i = s.indexOf(ql, i)) !== -1) { n++; i += ql.length; }
    }
    return n;
  } catch { return null; } // cross-origin
}
async function yank() {
  try { await navigator.clipboard.writeText(tab().url); flash('yanked: ' + shorten(tab().url, 44)); }
  catch { flash('clipboard blocked'); log('clipboard write failed'); }
}
function jumpToMedia() {
  const cands = tabs
    .map((t, i) => ({ t, i }))
    .filter((x) => x.t.media && x.i !== active)
    .sort((a, b) => b.t.mediaSince - a.t.mediaSince);
  if (cands.length) switchTab(cands[0].i);
  else flash('no media tab');
}

// ---------------- mode manager ----------------
let mode = 'NORMAL';
let lastFind = '';
let findTotal = null; // null = cross-origin, count unavailable
let findIdx = 0;

function bodyClasses() {
  return [
    'mode-' + mode.toLowerCase(),
    settings.tint && 'tint',
    settings.accent && 'accent',
    settings.fadeBadge && 'fadebadge',
    settings.showOverlay && 'showoverlay',
  ].filter(Boolean).join(' ');
}
function setMode(m, why) {
  if (mode === m) return;
  mode = m;
  log(`mode -> ${m}${why ? ' (' + why + ')' : ''}`);
  // Sync mode class to active frame document for cursor styling
  try {
    const d = tab().frame.contentDocument;
    if (d && d.body) {
      d.body.classList.toggle('mode-insert', m === 'INSERT');
      d.body.classList.toggle('mode-normal', m === 'NORMAL');
    }
  } catch { /* cross-origin */ }
  render();
  if (m === 'NORMAL') els.overlay.focus();
}
function toNormal(why) {
  try { // release any focused element inside the page
    const d = tab().frame.contentDocument;
    if (d && d.activeElement && d.activeElement.blur) d.activeElement.blur();
  } catch { /* cross-origin */ }
  setMode('NORMAL', why);
}
function toInsert(why) {
  setMode('INSERT', why);
  try { tab().frame.focus(); } catch { /* noop */ }
}

// ---------------- overlay: NORMAL-mode focus arbitration experiment ----------------
els.overlay.addEventListener('mousedown', (e) => {
  toInsert('click through overlay');
  // same-origin: if an editable element sits under the cursor, focus it
  try {
    const t = tab();
    const d = t.frame.contentDocument;
    const r = t.frame.getBoundingClientRect();
    const at = d.elementFromPoint(e.clientX - r.left, e.clientY - r.top);
    const editable = at && at.closest ? at.closest('input,textarea,select,[contenteditable]') : null;
    if (editable) { editable.focus(); log('focus forwarded to field under cursor'); }
  } catch { /* cross-origin: plain INSERT only */ }
});
// mouse escape hatch, especially for cross-origin INSERT where Esc is invisible
els.bar.addEventListener('mousedown', () => { if (mode === 'INSERT') toNormal('bar click'); });

// ---------------- keybinding engine ----------------
let pendingSeq = '';
let pendingCount = '';
let pendingTimer = null;
const count = () => Math.max(1, parseInt(pendingCount || '1', 10));

const NORMAL_BINDINGS = {
  'j':   () => scrollActive(0, SCROLL_PX * count()),
  'k':   () => scrollActive(0, -SCROLL_PX * count()),
  'C-d': () => scrollActive(0, pageAmount(0.5) * count()),
  'C-u': () => scrollActive(0, -pageAmount(0.5) * count()),
  'C-f': () => scrollActive(0, pageAmount(1) * count()),
  'C-b': () => scrollActive(0, -pageAmount(1) * count()),
  'gg':  () => scrollToPos('top'),
  'G':   () => scrollToPos('bottom'),
  'H':   () => historyNav(-1),
  'L':   () => historyNav(1),
  'r':   () => reloadTab(),
  'gt':  () => { pendingCount ? switchTab(count() - 1) : stepTab(1); showTabOverlay(false); },
  'gT':  () => { stepTab(-count()); showTabOverlay(false); },
  'g0':  () => { switchTab(0); showTabOverlay(false); },
  'g$':  () => { switchTab(tabs.length - 1); showTabOverlay(false); },
  'M':   () => jumpToMedia(),
  'i':   () => toInsert('i'),
  'o':   () => openEditor('open'),
  'O':   () => openEditor('open'), // poc alias; real browser: open in new tab
  '/':   () => openEditor('find'),
  ':':   () => openEditor('cmd'),
  'n':   () => {
    if (!lastFind) return;
    if (findActive(lastFind) && findTotal) findIdx = (findIdx % findTotal) + 1;
    render();
  },
  'N':   () => {
    if (!lastFind) return;
    if (findActive(lastFind, true) && findTotal) findIdx = ((findIdx - 2 + findTotal) % findTotal) + 1;
    render();
  },
  'yy':  () => yank(),
  ',t':  () => showTabOverlay(true),
  ',d':  () => togglePanel('debug'),
  ',x':  () => togglePanel('settings'),
  '?':   () => togglePanel('help'),
};
const PREFIX_SET = new Set();
for (const key of Object.keys(NORMAL_BINDINGS)) {
  for (let i = 1; i < key.length; i++) PREFIX_SET.add(key.slice(0, i));
}

function clearPending() {
  pendingSeq = '';
  pendingCount = '';
  clearTimeout(pendingTimer);
}
function schedulePendingTimeout() {
  clearTimeout(pendingTimer);
  pendingTimer = setTimeout(() => { clearPending(); render(); }, 1000);
}

function keyName(e) {
  if (e.metaKey) return null; // let the OS/browser keep Cmd-*
  if (e.key === 'Escape') return 'Escape';
  if (e.ctrlKey) {
    const k = e.key.toLowerCase();
    if (k === '[') return 'Escape';
    if (/^[a-z]$/.test(k)) return 'C-' + k;
    return null;
  }
  return e.key.length === 1 ? e.key : null;
}

window.addEventListener('keydown', (e) => {
  if (editor) return; // edit bar owns the keyboard while open
  const k = keyName(e);
  if (tabPicker && mode === 'NORMAL') { // sticky tab picker owns NORMAL keys
    if (!k && e.key !== 'Enter') return; // let OS/browser combos through
    e.preventDefault();
    if (e.key === 'Enter') { switchTab(tabPickerSel); hideTabOverlay(); render(); }
    else if (k === 'Escape') { hideTabOverlay(); render(); }
    else if (k === 'j' || k === 'C-n') { tabPickerSel = (tabPickerSel + 1) % tabs.length; renderTabOverlay(); }
    else if (k === 'k' || k === 'C-p') { tabPickerSel = (tabPickerSel - 1 + tabs.length) % tabs.length; renderTabOverlay(); }
    else if (/^[1-9]$/.test(k)) { switchTab(parseInt(k, 10) - 1); hideTabOverlay(); render(); }
    return;
  }
  if (!k) return;

  if (mode === 'INSERT') {
    if (k === 'Escape') { e.preventDefault(); toNormal('esc'); }
    return; // everything else belongs to the page
  }
  if (mode !== 'NORMAL') return; // COMMAND/SEARCH only exist with the editor open

  if (k === 'Escape') {
    if (closeAnyPanel()) return;
    if (!els.tabov.classList.contains('hidden')) { hideTabOverlay(); return; }
    if (pendingSeq || pendingCount) { clearPending(); render(); return; }
    if (lastFind) { clearFind(); render(); }
    return;
  }
  // counts: 3j, 12gt … ('0' alone is not a count start)
  if (!pendingSeq && /^[0-9]$/.test(k) && !(k === '0' && !pendingCount)) {
    pendingCount += k;
    schedulePendingTimeout();
    e.preventDefault();
    render();
    return;
  }
  const cand = pendingSeq + k;
  const fn = NORMAL_BINDINGS[cand];
  if (fn) {
    e.preventDefault();
    fn();            // count() must still see pendingCount here
    clearPending();
    render();
    return;
  }
  if (PREFIX_SET.has(cand)) {
    pendingSeq = cand;
    schedulePendingTimeout();
    e.preventDefault();
    render();
    return;
  }
  if (pendingSeq || pendingCount) {
    flash(`unknown: ${pendingCount}${cand}`);
    clearPending();
    render();
  }
});

// ---------------- edit bar: open / find / ex-command ----------------
let editor = null; // { kind, wrap, input, hint }

function openEditor(kind) {
  closeEditor();
  const useTop = settings.editPosition === 'top';
  const wrap = useTop ? els.ebTop : els.ebBottom;
  const input = useTop ? els.ebTopInput : els.ebInput;
  const hint = useTop ? els.ebTopHint : els.ebHint;
  const promptEl = useTop ? els.ebTopPrompt : els.ebPrompt;
  promptEl.textContent = kind === 'open' ? 'open' : kind === 'find' ? '/' : ':';
  input.value = kind === 'open' && settings.prefill !== 'empty' ? tab().url : '';
  hint.textContent = '';
  wrap.classList.remove('hidden');
  els.addr.classList.toggle('hidden', !useTop);
  els.bar.classList.toggle('editing', !useTop); // full-width input experiment
  editor = { kind, wrap, input, hint };
  if (kind === 'open') openSuggest();
  setMode(kind === 'find' ? 'SEARCH' : 'COMMAND', kind);
  input.focus();
  if (kind === 'open' && settings.prefill === 'select') input.select();
  if (kind === 'open' && settings.prefill === 'end') {
    input.setSelectionRange(input.value.length, input.value.length);
  }
  updateEditorHint();
}

function closeEditor() {
  if (!editor) return;
  editor.wrap.classList.add('hidden');
  editor.input.value = '';
  editor.hint.textContent = '';
  editor = null;
  els.addr.classList.remove('hidden');
  els.bar.classList.remove('editing');
  closeSuggest();
}

function classify(v) {
  if (/^https?:\/\//i.test(v)) return { type: 'go', url: v };
  if (v.startsWith('sites/') || v.startsWith('/')) return { type: 'go', url: v };
  if (/^localhost(:\d+)?([/?#]|$)/.test(v) || /^\d{1,3}(\.\d{1,3}){3}(:\d+)?([/?#]|$)/.test(v)) {
    return { type: 'go', url: 'http://' + v };
  }
  if (/^[^\s/?#]+\.[^\s/?#]{2,}([/?#]\S*)?$/.test(v)) return { type: 'go', url: 'https://' + v };
  return { type: 'search', q: v };
}

const COMMANDS = ['open', 'reload', 'help', 'debug', 'settings', 'yank'];
function cmdHint(v) {
  if (!v) return COMMANDS.join('  ');
  return COMMANDS.filter((c) => c.startsWith(v)).join('  ');
}
function runCommand(v) {
  const [cmd, ...rest] = v.split(/\s+/);
  const arg = rest.join(' ');
  switch (cmd) {
    case 'open': case 'o':
      if (arg) {
        const c = classify(arg);
        navigate(tab(), c.type === 'go' ? c.url : SEARCH_URLS[settings.engine] + encodeURIComponent(arg));
      }
      break;
    case 'reload': reloadTab(); break;
    case 'help': togglePanel('help'); break;
    case 'debug': togglePanel('debug'); break;
    case 'settings': togglePanel('settings'); break;
    case 'yank': yank(); break;
    default: flash(`unknown command: ${cmd}`); log(`unknown :${cmd}`);
  }
}

function updateEditorHint() {
  if (!editor) return;
  const v = editor.input.value.trim();
  if (editor.kind === 'open') {
    const c = classify(v);
    editor.hint.textContent = !v ? '' : c.type === 'go'
      ? `→ go to ${shorten(c.url, 48)}`
      : `→ search ${settings.engine}: ${shorten(v, 32)}`;
    updateSuggest();
  } else if (editor.kind === 'find') {
    if (v) {
      findActive(v); // live find-as-you-type
      const total = countMatches(v);
      editor.hint.textContent = `[${total === null ? '?' : total} found]`;
    } else {
      editor.hint.textContent = '';
    }
  } else {
    editor.hint.textContent = cmdHint(v);
  }
}

function commitEditor() {
  const kind = editor.kind;
  const v = editor.input.value.trim();
  closeEditor();
  if (v) {
    if (kind === 'open') {
      const c = classify(v);
      navigate(tab(), c.type === 'go' ? c.url : SEARCH_URLS[settings.engine] + encodeURIComponent(v));
    } else if (kind === 'find') {
      lastFind = v;
      findTotal = countMatches(v);
      try { // Enter = first occurrence: rewind to top, then find
        const w = tab().frame.contentWindow;
        w.getSelection().collapse(w.document.body, 0);
      } catch { /* cross-origin */ }
      findIdx = findActive(v) ? 1 : 0;
    } else {
      runCommand(v);
    }
  }
  toNormal();
}
function cancelEditor() {
  closeEditor();
  toNormal('esc');
}

for (const input of [els.ebInput, els.ebTopInput]) {
  input.addEventListener('keydown', (e) => {
    e.stopPropagation();
    if (e.key === 'Escape') { e.preventDefault(); cancelEditor(); return; }
    if (e.key === 'Enter') {
      e.preventDefault();
      if (suggest && suggest.sel >= 0) acceptSuggest(suggest.items[suggest.sel]);
      else commitEditor();
      return;
    }
    if (editor && editor.kind === 'open') {
      if (e.key === 'ArrowUp' || (e.ctrlKey && e.key === 'p')) { e.preventDefault(); suggestUp(); }
      else if (e.key === 'ArrowDown' || (e.ctrlKey && e.key === 'n')) { e.preventDefault(); suggestDown(); }
      else if (e.key === 'Tab') {
        e.preventDefault();
        if (suggest && suggest.items.length) {
          const it = suggest.items[Math.max(0, suggest.sel)];
          input.value = it.url;
          input.setSelectionRange(input.value.length, input.value.length);
          updateSuggest();
          updateEditorHint();
        }
      }
    }
  });
  input.addEventListener('input', updateEditorHint);
}

// ---------------- suggestions: upward combobox experiment ----------------
// POC uses mock data (open tabs + fake history). Real browser: the Rust core
// fetches Google/DDG suggest server-side (no CORS) and streams items in —
// this UI stays identical.
const MOCK_HISTORY = [
  { title: 'MDN Web Docs', url: 'https://developer.mozilla.org' },
  { title: 'Hacker News', url: 'https://news.ycombinator.com' },
  { title: 'Stack Overflow', url: 'https://stackoverflow.com' },
  { title: 'dev.to', url: 'https://dev.to' },
  { title: 'lobste.rs', url: 'https://lobste.rs' },
  { title: 'Wikipedia', url: 'https://en.wikipedia.org' },
  { title: 'rust-lang.org', url: 'https://www.rust-lang.org' },
  { title: 'example.com', url: 'https://example.com' },
  { title: 'Scroll Lab (local)', url: 'sites/scroll.html' },
  { title: 'Form Lab (local)', url: 'sites/form.html' },
];

let suggest = null; // { items: [], sel: -1 }

function fuzzy(q, s) {
  let qi = 0, score = 0, last = -2;
  const sl = s.toLowerCase(), ql = q.toLowerCase();
  for (let si = 0; si < sl.length && qi < ql.length; si++) {
    if (sl[si] === ql[qi]) {
      score += si === last + 1 ? 2 : 1;
      if (si === 0 || '/-.'.includes(sl[si - 1])) score += 2; // word boundary bonus
      last = si; qi++;
    }
  }
  return qi === ql.length ? score : -1;
}

function buildSuggestItems(q) {
  const sources = [
    ...tabs.map((t, i) => ({ title: t.title || t.url, url: t.url, tag: `tab ${i + 1}`, boost: 5 })),
    ...MOCK_HISTORY.map((h) => ({ ...h, tag: 'hist', boost: 0 })),
  ];
  const items = [];
  for (const s of sources) {
    const score = q ? Math.max(fuzzy(q, s.title), fuzzy(q, s.url)) : 1;
    if (score >= 0) items.push({ ...s, score: score + s.boost });
  }
  items.sort((a, b) => b.score - a.score);
  const top = items.slice(0, 8);
  if (q) top.push({
    title: `search ${settings.engine} for "${q}"`,
    url: SEARCH_URLS[settings.engine] + encodeURIComponent(q),
    tag: 'search', score: -1,
  });
  return top;
}

function openSuggest() {
  suggest = { items: buildSuggestItems(editor.input.value.trim()), sel: -1 };
  renderSuggest();
}
function updateSuggest() {
  if (!suggest) return;
  suggest.items = buildSuggestItems(editor.input.value.trim());
  if (suggest.sel >= suggest.items.length) suggest.sel = suggest.items.length - 1;
  renderSuggest();
}
function closeSuggest() {
  suggest = null;
  els.suggest.classList.add('hidden');
}
function suggestUp() { // visually up = away from the bar = next-best match
  if (!suggest || !suggest.items.length) return;
  suggest.sel = Math.min(suggest.sel + 1, suggest.items.length - 1);
  renderSuggest();
}
function suggestDown() { // visually down = toward the bar / input
  if (!suggest) return;
  suggest.sel = Math.max(suggest.sel - 1, -1);
  renderSuggest();
}
function renderSuggest() {
  if (!suggest || !suggest.items.length) { closeSuggest(); return; }
  els.suggest.innerHTML = '';
  suggest.items.forEach((it, i) => {
    const row = document.createElement('div');
    row.className = 'srow' + (i === suggest.sel ? ' sel' : '');
    const main = document.createElement('span');
    main.textContent = it.title;
    const url = document.createElement('span');
    url.className = 'surl';
    url.textContent = shorten(it.url, 56);
    const tag = document.createElement('span');
    tag.className = 'stag';
    tag.textContent = it.tag;
    row.append(main, url, tag);
    row.addEventListener('mousedown', (e) => { e.preventDefault(); acceptSuggest(it); });
    els.suggest.appendChild(row);
  });
  els.suggest.className = 'dock-' + settings.editPosition;
  els.suggest.classList.remove('hidden');
}
function acceptSuggest(it) {
  closeEditor();
  navigate(tab(), it.url);
  toNormal();
}

// ---------------- tab overlay: transient list + sticky picker ----------------
let tabovTimer = null;
let tabPicker = false;
let tabPickerSel = 0;

function showTabOverlay(sticky) {
  tabPicker = sticky;
  tabPickerSel = active;
  els.tabov.classList.remove('hidden');
  renderTabOverlay();
  if (!sticky) pokeTabOverlayTimer();
}
function hideTabOverlay() {
  tabPicker = false;
  clearTimeout(tabovTimer);
  els.tabov.classList.add('hidden');
}
function pokeTabOverlayTimer() {
  clearTimeout(tabovTimer);
  tabovTimer = setTimeout(() => { if (!tabPicker) els.tabov.classList.add('hidden'); }, 1400);
}
function renderTabOverlay() {
  if (els.tabov.classList.contains('hidden')) return;
  els.tabov.innerHTML = '';
  tabs.forEach((t, i) => {
    const row = document.createElement('div');
    row.className = 'trow'
      + (i === active ? ' active' : '')
      + (tabPicker && i === tabPickerSel ? ' sel' : '');
    const num = document.createElement('span');
    num.className = 'tnum';
    num.textContent = i + 1;
    const main = document.createElement('span');
    main.className = 'tmain';
    main.textContent = (t.media ? '🔊 ' : '') + (t.title || t.url);
    const url = document.createElement('span');
    url.className = 'turl';
    url.textContent = shorten(t.url, 48);
    row.append(num, main, url);
    row.addEventListener('mousedown', () => { switchTab(i); hideTabOverlay(); });
    els.tabov.appendChild(row);
  });
}

// ---------------- panels ----------------
function togglePanel(name) {
  const elx = { help: els.help, settings: els.settings, debug: els.debug }[name];
  elx.classList.toggle('hidden');
  if (name === 'debug' && !elx.classList.contains('hidden')) renderDebug();
  log(`panel ${name} ${elx.classList.contains('hidden') ? 'closed' : 'open'}`);
}
function closeAnyPanel() {
  for (const elx of [els.help, els.settings, els.debug]) {
    if (!elx.classList.contains('hidden')) { elx.classList.add('hidden'); return true; }
  }
  return false;
}

// ---------------- rendering ----------------
const SPIN = '⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏';
let spinIdx = 0;

function render() {
  document.body.className = bodyClasses();
  els.badge.textContent = mode;
  els.pending.textContent = (pendingCount + pendingSeq)
    || (mode === 'INSERT' && !tab().sameOrigin ? 'click bar → NORMAL' : '');
  els.tabpos.textContent = `${active + 1}/${tabs.length}`;
  const audible = tabs.filter((t) => t.media).length;
  els.media.textContent = audible ? `🔊 ${audible}` : '';
  renderAddr();
  els.findstate.textContent = lastFind
    ? `${lastFind} [${findIdx}/${findTotal === null ? '?' : findTotal}]`
    : '';
  renderLoadstate();
  renderClock();
}

function renderAddr() {
  const t = tab();
  let s = '';
  if (settings.urlPlacement === 'statusline') {
    s = shorten(t.url, 64);
  } else if (settings.urlPlacement === 'hybrid') {
    let where = t.url;
    try {
      const u = new URL(t.url);
      where = t.url.startsWith(location.origin) ? u.pathname : u.hostname;
    } catch { /* keep raw */ }
    s = t.title ? `${t.title} · ${where}` : where;
  }
  els.addr.textContent = s;
  els.addr.title = t.url;
}

function renderLoadstate() {
  const t = tab();
  const label = {
    loading: `● loading ${SPIN[spinIdx]}`,
    slow: `● slow… ${SPIN[spinIdx]}`,
    ok: t.faded ? '·' : '✓ loaded',
    error: '✗ error (timeout)',
    blocked: '⛔ blocked (x-frame-options)',
  }[t.status] || '';
  els.loadstate.textContent = label;
  els.loadstate.dataset.s = t.status === 'ok' && t.faded ? 'okfade' : t.status;
}

function renderClock() {
  els.clock.textContent = new Date().toTimeString().slice(0, 5);
}

setInterval(() => {
  if (tab().status === 'loading' || tab().status === 'slow') {
    spinIdx = (spinIdx + 1) % SPIN.length;
    renderLoadstate();
  }
}, 90);
setInterval(renderClock, 20000);

// media signal: poll same-origin frames for playing audio/video (mini §5)
setInterval(() => {
  let changed = false;
  for (const t of tabs) {
    let playing = false;
    try {
      const d = t.frame.contentDocument;
      playing = !!d && [...d.querySelectorAll('audio,video')].some((m) => !m.paused && !m.ended);
    } catch { /* cross-origin */ }
    if (playing !== t.media) {
      t.media = playing;
      if (playing) t.mediaSince = Date.now();
      if (playing && t !== tab()) log('background tab became audible 🔊 — press M');
      changed = true;
    }
  }
  if (changed) { render(); renderTabOverlay(); }
}, 1000);

// ---------------- settings panel wiring ----------------
function bindRadio(name) {
  for (const r of document.querySelectorAll(`input[name="${name}"]`)) {
    r.checked = r.value === settings[name];
    r.addEventListener('change', () => { settings[name] = r.value; saveSettings(); render(); });
  }
}
function initSettingsPanel() {
  bindRadio('urlPlacement');
  bindRadio('editPosition');
  bindRadio('prefill');
  const eng = $('set-engine');
  eng.value = settings.engine;
  eng.addEventListener('change', () => { settings.engine = eng.value; saveSettings(); });
  for (const key of ['tint', 'accent', 'fadeBadge', 'showOverlay']) {
    const cb = $('set-' + key);
    cb.checked = settings[key];
    cb.addEventListener('change', () => { settings[key] = cb.checked; saveSettings(); render(); });
  }
}

// ---------------- init ----------------
tabs.forEach((_, i) => wireFrame(i));
tabs[0].frame.classList.add('active');
initSettingsPanel();
render();
els.overlay.focus();
log('vimzen poc ready — ? help · ,x experiments · ,d debug log');
