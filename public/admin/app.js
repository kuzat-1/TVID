const $ = (id) => document.getElementById(id);
let token = sessionStorage.getItem('tanho_admin_token') || '';
let config = { blacklist: [], custom: {}, settings: {} };

function authHeaders() {
  return { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` };
}

async function api(path, opts = {}) {
  const res = await fetch(path, opts);
  if (res.status === 401 || res.status === 403) {
    logout();
    throw new Error('Unauthorized');
  }
  return res.json();
}

async function login() {
  token = $('token').value.trim();
  if (!token) return;
  try {
    const res = await fetch('/api/admin/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token }),
    });
    const data = await res.json();
    if (data.success) {
      sessionStorage.setItem('tanho_admin_token', token);
      boot();
      return;
    }
    if (data.error === 'blocked') {
      const hours = Math.ceil((data.retryAfter || 86400) / 3600);
      $('loginError').textContent =
        `Доступ заблокирован на ${hours} ч. Повторите позже.`;
    } else {
      $('loginError').textContent =
        `Неверный токен. Осталось попыток: ${data.attemptsLeft ?? 0}`;
    }
    $('loginError').classList.remove('hidden');
  } catch {
    $('loginError').textContent = 'Нет связи с сервером';
    $('loginError').classList.remove('hidden');
  }
}

function logout() {
  token = '';
  sessionStorage.removeItem('tanho_admin_token');
  $('app').classList.add('hidden');
  $('login').classList.remove('hidden');
}

async function boot() {
  try {
    const data = await api('/api/admin/config', { headers: authHeaders() });
    if (!data.success) throw new Error('bad config');
    config = data;
    $('login').classList.add('hidden');
    $('app').classList.remove('hidden');
    $('loginError').classList.add('hidden');
    fillSettings();
    renderVideos();
    loadStats();
  } catch {
    $('loginError').classList.remove('hidden');
  }
}

async function loadStats() {
  try {
    const s = await api('/api/admin/stats');
    if (s.success) {
      $('mViews').textContent = s.views;
      $('mToday').textContent = s.viewsToday;
      $('mBlocked').textContent = `${s.blacklist} / ${s.customCount}`;
      $('mReports').textContent = s.reports ?? 0;
    }
  } catch {}
}

function allKeys() {
  const keys = new Set([
    ...config.blacklist,
    ...Object.keys(config.custom),
  ]);
  return [...keys];
}

function renderVideos() {
  const q = $('search').value.toLowerCase().trim();
  const box = $('videoList');
  box.innerHTML = '';
  for (const key of allKeys()) {
    const c = config.custom[key] || {};
    const title = c.title || '';
    if (
      q &&
      !key.toLowerCase().includes(q) &&
      !title.toLowerCase().includes(q)
    ) {
      continue;
    }
    const blocked = config.blacklist.includes(key);
    const hidden = c.is_hidden === true;
    const row = document.createElement('div');
    row.className = 'vrow';
    row.innerHTML = `
      <div class="vkey">${key}${blocked ? ' • в blacklist' : ''}${hidden ? ' • скрыто' : ''}</div>
      <div class="vtitle">${escapeHtml(title) || '(без названия)'}</div>
      <div class="actions"></div>`;
    const acts = row.querySelector('.actions');
    const mkBtn = (label, cls, fn) => {
      const b = document.createElement('button');
      b.textContent = label;
      if (cls) b.className = cls;
      b.onclick = fn;
      acts.appendChild(b);
    };
    mkBtn(blocked ? 'Вернуть' : 'Удалить', blocked ? '' : 'danger', async () => {
      const bl = new Set(config.blacklist);
      if (blocked) bl.delete(key);
      else bl.add(key);
      await saveConfig({ blacklist: [...bl] });
    });
    mkBtn(hidden ? 'Показать' : 'Скрыть', 'warn', async () => {
      const custom = { ...config.custom };
      custom[key] = { ...(custom[key] || {}), is_hidden: !hidden };
      await saveConfig({ custom });
    });
    mkBtn('Редактировать', '', () => {
      const t = prompt('Название:', title);
      if (t === null) return;
      const th = prompt('URL обложки:', c.thumb || '');
      if (th === null) return;
      const custom = { ...config.custom };
      custom[key] = { ...(custom[key] || {}), title: t.trim(), thumb: th.trim() };
      saveConfig({ custom });
    });
    mkBtn('Обновить обложку', 'ghost', async () => {
      const b = acts.querySelector('button:last-child');
      const old = b.textContent;
      b.textContent = '...';
      try {
        const r = await api('/api/catalog/resolve', {
          method: 'POST',
          headers: authHeaders(),
          body: JSON.stringify({ url: 'https://vk.com/video' + key }),
        });
        if (r.success && r.thumb) {
          const custom = { ...config.custom };
          custom[key] = { ...(custom[key] || {}), thumb: r.thumb, title: r.title || title };
          await saveConfig({ custom });
        } else {
          alert('Не удалось обновить: ' + (r.error || 'пустая обложка'));
        }
      } catch {
        alert('Ошибка сети');
      }
      b.textContent = old;
    });
    box.appendChild(row);
  }
  if (!box.children.length) {
    box.innerHTML = '<p class="muted">Список пуст. Добавьте ключ видео вручную.</p>';
  }
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (m) => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;',
  })[m]);
}

async function saveConfig(patch) {
  const data = await api('/api/admin/config', {
    method: 'POST',
    headers: authHeaders(),
    body: JSON.stringify(patch),
  });
  if (data.success) {
    config = data;
    renderVideos();
    loadStats();
  }
  return data;
}

function fillSettings() {
  const s = config.settings || {};
  $('sYandex').checked = !!s.yandexEnabled;
  $('sFeedEvery').value = s.feedAdEvery ?? 5;
  $('sReelsEvery').value = s.reelsAdEvery ?? 6;
  $('sFeedBlock').value = s.feedBlockId ?? '';
  $('sReelsBlock').value = s.reelsBlockId ?? '';
  $('sVersion').value = s.latestVersion ?? '';
  $('sForce').checked = !!s.forceUpdate;
  $('sAppPass').value = s.adminAppPass ?? '';
  $('sVkToken').value = s.vkToken ?? '';
  $('sVkCookies').value = s.vkCookies ?? '';
  $('sVkAppId').value = s.vkAppId ?? '';
  $('sPlayerEvery').value = s.playerAdEvery ?? 4;
  markPlayerMode(s.playerAdMode || 'off');
  $('sCacheTtl').value = s.cacheTtlHours ?? 6;
  markMode(s.videoSource || 'vkapi');
  loadCacheInfo();
  $('sCustomHtml').value = s.customHtml ?? '';
  htmlPlaces.htmlPlayer = !!s.htmlPlayer;
  htmlPlaces.htmlOpen = !!s.htmlOpen;
  htmlPlaces.htmlFeed = !!s.htmlFeed;
  htmlPlaces.htmlReels = !!s.htmlReels;
  if (
    !htmlPlaces.htmlPlayer &&
    !htmlPlaces.htmlOpen &&
    !htmlPlaces.htmlFeed &&
    !htmlPlaces.htmlReels &&
    s.customHtmlEnabled
  ) {
    const p = s.customHtmlPlacement || 'player';
    if (p === 'player' || p === 'both') htmlPlaces.htmlPlayer = true;
    if (p === 'feed' || p === 'both') htmlPlaces.htmlFeed = true;
  }
  markHtmlPlaces();
}

async function saveSettings() {
  await saveConfig({
    settings: {
      yandexEnabled: $('sYandex').checked,
      feedAdEvery: parseInt($('sFeedEvery').value, 10) || 5,
      reelsAdEvery: parseInt($('sReelsEvery').value, 10) || 6,
      feedBlockId: $('sFeedBlock').value.trim(),
      reelsBlockId: $('sReelsBlock').value.trim(),
      latestVersion: $('sVersion').value.trim(),
      forceUpdate: $('sForce').checked,
      adminAppPass: $('sAppPass').value.trim(),
      customHtmlEnabled:
        htmlPlaces.htmlPlayer ||
        htmlPlaces.htmlOpen ||
        htmlPlaces.htmlFeed ||
        htmlPlaces.htmlReels,
      customHtmlPlacement: currentHtmlPlacement,
      customHtml: $('sCustomHtml').value,
      htmlPlayer: htmlPlaces.htmlPlayer,
      htmlOpen: htmlPlaces.htmlOpen,
      htmlFeed: htmlPlaces.htmlFeed,
      htmlReels: htmlPlaces.htmlReels,
      vkToken: $('sVkToken').value.trim(),
      vkCookies: $('sVkCookies').value,
      vkAppId: $('sVkAppId').value.trim(),
      playerAdMode: currentPlayerMode,
      playerAdEvery: parseInt($('sPlayerEvery').value, 10) || 4,
      cacheTtlHours: parseInt($('sCacheTtl').value, 10) || 6,
      videoSource: currentMode,
    },
  });
  $('saveMsg').textContent = 'Сохранено ✓';
  setTimeout(() => ($('saveMsg').textContent = ''), 2500);
}

$('loginBtn').onclick = login;
$('token').addEventListener('keydown', (e) => {
  if (e.key === 'Enter') login();
});
$('logoutBtn').onclick = logout;
$('burger').onclick = () => $('drawer').classList.toggle('open');
function showTab(name) {
  document
    .querySelectorAll('#drawer button')
    .forEach((x) => x.classList.toggle('active', x.dataset.tab === name));
  $('drawer').classList.remove('open');
  for (const t of ['dash', 'videos', 'settings']) {
    $('tab-' + t).classList.toggle('hidden', t !== name);
  }
  try {
    sessionStorage.setItem('tanho_admin_tab', name);
  } catch {}
}

document.querySelectorAll('#drawer button').forEach((b) => {
  b.onclick = () => showTab(b.dataset.tab);
});
$('refreshStats').onclick = loadStats;
$('search').oninput = renderVideos;
$('saveSettings').onclick = saveSettings;
$('addBlock').onclick = async () => {
  const key = $('fKey').value.trim();
  if (!key) return;
  const bl = new Set(config.blacklist);
  bl.add(key);
  await saveConfig({ blacklist: [...bl] });
  $('fKey').value = '';
};
$('addCustom').onclick = async () => {
  const key = $('fKey').value.trim();
  if (!key) return;
  const custom = { ...config.custom };
  custom[key] = {
    ...(custom[key] || {}),
    title: $('fTitle').value.trim(),
    thumb: $('fThumb').value.trim(),
  };
  await saveConfig({ custom });
  $('fKey').value = '';
  $('fTitle').value = '';
  $('fThumb').value = '';
};

async function loadCatalog() {
  try {
    const data = await api('/api/catalog');
    const box = $('catalogList');
    box.innerHTML = '';
    for (const item of data.items || []) {
      const row = document.createElement('div');
      row.className = 'vrow';
      row.innerHTML = `
        <div class="vtitle">${escapeHtml(item.title || '')}</div>
        <div class="vkey">${escapeHtml(item.key || '')}</div>
        <div class="actions"></div>`;
      const b = document.createElement('button');
      b.textContent = 'Убрать';
      b.className = 'danger';
      b.onclick = async () => {
        await fetch('/api/catalog/' + encodeURIComponent(item.key), {
          method: 'DELETE',
          headers: authHeaders(),
        });
        loadCatalog();
        loadStats();
      };
      row.querySelector('.actions').appendChild(b);
      box.appendChild(row);
    }
    if (!box.children.length) {
      box.innerHTML = '<p class="muted">Каталог пуст.</p>';
    }
  } catch {}
}

let currentMode = 'vkapi';

function markMode(mode) {
  currentMode = mode === 'parser' ? 'parser' : 'vkapi';
  paintToggle('modeParser', currentMode === 'parser');
  paintToggle('modeVkapi', currentMode === 'vkapi');
}

$('modeParser').onclick = () => markMode('parser');
$('modeVkapi').onclick = () => markMode('vkapi');

let currentHtmlPlacement = 'player';

const htmlPlaces = {
  htmlPlayer: false,
  htmlOpen: false,
  htmlFeed: false,
  htmlReels: false,
};

function paintToggle(id, on) {
  const btn = $(id);
  if (!btn.dataset.label) btn.dataset.label = btn.textContent;
  btn.classList.toggle('mode-on', on);
  btn.textContent = (on ? '✓ ' : '') + btn.dataset.label;
}

function markHtmlPlaces() {
  paintToggle('hPlayer', htmlPlaces.htmlPlayer);
  paintToggle('hOpen', htmlPlaces.htmlOpen);
  paintToggle('hFeed', htmlPlaces.htmlFeed);
  paintToggle('hReels', htmlPlaces.htmlReels);
  const any =
    htmlPlaces.htmlPlayer ||
    htmlPlaces.htmlOpen ||
    htmlPlaces.htmlFeed ||
    htmlPlaces.htmlReels;
  currentHtmlPlacement = any ? 'player' : 'off';
}

$('hPlayer').onclick = () => {
  htmlPlaces.htmlPlayer = !htmlPlaces.htmlPlayer;
  markHtmlPlaces();
};
$('hOpen').onclick = () => {
  htmlPlaces.htmlOpen = !htmlPlaces.htmlOpen;
  markHtmlPlaces();
};
$('hFeed').onclick = () => {
  htmlPlaces.htmlFeed = !htmlPlaces.htmlFeed;
  markHtmlPlaces();
};
$('hReels').onclick = () => {
  htmlPlaces.htmlReels = !htmlPlaces.htmlReels;
  markHtmlPlaces();
};

let currentPlayerMode = 'off';

function markPlayerMode(mode) {
  currentPlayerMode =
    mode === 'html' ? 'html' : mode === 'yandex' ? 'yandex' : 'off';
  paintToggle('pModeOff', currentPlayerMode === 'off');
  paintToggle('pModeHtml', currentPlayerMode === 'html');
  paintToggle('pModeYandex', currentPlayerMode === 'yandex');
}

$('pModeOff').onclick = () => markPlayerMode('off');
$('pModeHtml').onclick = () => markPlayerMode('html');
$('pModeYandex').onclick = () => markPlayerMode('yandex');

async function loadCacheInfo() {
  try {
    const res = await fetch('/api/stream-vk/cache', {
      headers: authHeaders(),
    });
    const data = await res.json();
    if (data.success) {
      $('cacheSize').textContent = data.size;
      $('cacheTtl').textContent = data.ttlHours;
    }
  } catch {}
}

$('clearCache').onclick = async () => {
  if (!confirm('Очистить весь кэш видео?')) return;
  try {
    await fetch('/api/stream-vk/cache', {
      method: 'DELETE',
      headers: authHeaders(),
    });
    loadCacheInfo();
  } catch {}
};

$('syncBtn').onclick = async () => {
  const link = $('syncLink').value.trim();
  if (!link) return;
  $('syncBtn').textContent = 'Синхронизирую...';
  $('syncMsg').textContent = 'Тяну список, это может занять минуту...';
  try {
    const res = await fetch('/api/sync', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ url: link }),
    });
    const data = await res.json();
    if (data.success) {
      $('syncMsg').textContent =
        `Найдено: ${data.found}, добавлено новых: ${data.added}, пропущено повторов: ${data.skipped}`;
      $('syncLink').value = '';
      loadCatalog();
      loadStats();
    } else {
      $('syncMsg').textContent = 'Не получилось: ' + (data.error || 'ошибка');
    }
  } catch {
    $('syncMsg').textContent = 'Нет связи с сервером';
  }
  $('syncBtn').textContent = 'Синхронизировать';
};

let activeSource = '';

async function loadSources() {
  try {
    const data = await api('/api/catalog/sources', {
      headers: authHeaders(),
    });
    const box = $('sourceChips');
    box.innerHTML = '';
    const all = document.createElement('button');
    all.textContent = 'Все';
    if (!activeSource) all.classList.add('mode-on');
    all.onclick = () => {
      activeSource = '';
      loadSources();
    };
    box.appendChild(all);
    for (const s of data.sources || []) {
      const b = document.createElement('button');
      b.textContent = `${s.name} (${s.count})`;
      if (activeSource === s.name) b.classList.add('mode-on');
      b.onclick = () => {
        activeSource = s.name;
        loadSources();
        showSource(s);
      };
      box.appendChild(b);
    }
    if (!activeSource) $('sourceBar').classList.add('hidden');
  } catch {}
}

async function showSource(s) {
  $('sourceBar').classList.remove('hidden');
  $('sourceTitle').textContent = s.name;
  $('sourceStats').textContent =
    `Всего: ${s.count} • работают: ${s.ok} • битые: ${s.bad}`;
  $('sourceSyncBtn').onclick = async () => {
    if (!s.url) {
      alert('У этого источника нет ссылки для синхронизации');
      return;
    }
    $('sourceSyncBtn').textContent = 'Синхронизирую...';
    try {
      const res = await fetch('/api/sync', {
        method: 'POST',
        headers: authHeaders(),
        body: JSON.stringify({ url: s.url }),
      });
      const data = await res.json();
      if (data.success) {
        $('sourceStats').textContent =
          `Найдено: ${data.found}, новых: ${data.added}, повторов: ${data.skipped}`;
        loadSources();
        loadStats();
      } else {
        $('sourceStats').textContent = 'Ошибка: ' + (data.error || '');
      }
    } catch {
      $('sourceStats').textContent = 'Нет связи';
    }
    $('sourceSyncBtn').textContent = 'Синхронизировать';
  };
  const box = $('sourceVideos');
  box.innerHTML = '<p class="muted">Загружаю...</p>';
  try {
    const res = await fetch(
      '/api/catalog?limit=100&source=' + encodeURIComponent(s.name),
      { headers: authHeaders() }
    );
    const data = await res.json();
    box.innerHTML = '';
    for (const v of data.items || []) {
      const row = document.createElement('div');
      row.className = 'vrow';
      const good = v.ok !== false;
      row.innerHTML = `
        <div style="display:flex;gap:10px;align-items:center">
          ${v.thumb ? `<img class="vthumb" src="${v.thumb}" loading="lazy" onerror="this.style.display='none'">` : ''}
          <div style="flex:1;min-width:0">
            <div class="vtitle">${escapeHtml(v.title || '')}
              <span class="badge ${good ? 'ok' : 'bad'}">${good ? 'работает' : 'битое'}</span>
              <span class="badge ${v.vertical ? 'warn' : ''}">${v.vertical ? 'вертикальное → Reels' : 'горизонтальное'}</span>
            </div>
            <div class="vkey">${escapeHtml(v.key || '')}</div>
          </div>
          <div class="actions"></div>
        </div>`;
      const acts = row.querySelector('.actions');
      const mkBtn = (label, cls, fn) => {
        const b = document.createElement('button');
        b.textContent = label;
        if (cls) b.className = cls;
        b.onclick = fn;
        acts.appendChild(b);
      };
      mkBtn('Обновить обложку', 'ghost', async () => {
        const b = acts.querySelector('button:last-child');
        const old = b.textContent;
        b.textContent = '...';
        try {
          const r = await api('/api/catalog/resolve', {
            method: 'POST',
            headers: authHeaders(),
            body: JSON.stringify({ url: 'https://vk.com/video' + v.key }),
          });
          if (r.success && r.thumb) {
            const res = await fetch('/api/catalog/' + encodeURIComponent(v.key), {
              method: 'POST',
              headers: authHeaders(),
              body: JSON.stringify({ ...v, thumb: r.thumb, title: r.title || v.title }),
            });
            if (res.ok) {
              showSource(s);
            } else {
              alert('Не сохранилось');
            }
          } else {
            alert('Не удалось: ' + (r.error || 'пусто'));
          }
        } catch {
          alert('Ошибка сети');
        }
        b.textContent = old;
      });
      box.appendChild(row);
    }
    if (!box.children.length) {
      box.innerHTML = '<p class="muted">Пусто.</p>';
    }
  } catch {
    box.innerHTML = '<p class="muted">Ошибка загрузки.</p>';
  }
}

const _boot3 = boot;
boot = async function () {
  await _boot3();
  loadSources();
  let tab = 'dash';
  try {
    tab = sessionStorage.getItem('tanho_admin_tab') || 'dash';
  } catch {}
  if (!['dash', 'videos', 'settings'].includes(tab)) tab = 'dash';
  showTab(tab);
};

$('addCatalog').onclick = async () => {
  const link = $('cLink').value.trim();
  if (!link) return;
  $('addCatalog').textContent = 'Распознаю...';
  try {
    const meta = await api('/api/catalog/resolve', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ url: link }),
    });
    if (!meta.success) throw new Error('bad');
    await api('/api/catalog', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify(meta),
    });
    $('cLink').value = '';
    loadCatalog();
    loadStats();
  } catch {
    alert('Не удалось распознать видео');
  }
  $('addCatalog').textContent = 'Распознать и добавить';
};

const _origRenderVideos = renderVideos;
renderVideos = function () {
  _origRenderVideos();
  loadCatalog();
};

async function loadSuggest() {
  try {
    const data = await api('/api/suggest', { headers: authHeaders() });
    const box = $('suggestList');
    box.innerHTML = '';
    for (let i = 0; i < (data.items || []).length; i++) {
      const item = data.items[i];
      const row = document.createElement('div');
      row.className = 'vrow';
      row.innerHTML = `
        <div class="vkey">${escapeHtml(item.url || '')}</div>
        <div class="vtitle">${escapeHtml(item.ts || '')}</div>
        <div class="actions"></div>`;
      const acts = row.querySelector('.actions');
      const ok = document.createElement('button');
      ok.textContent = 'В каталог';
      ok.onclick = async () => {
        ok.textContent = '...';
        const r = await api(`/api/suggest/${i}/approve`, {
          method: 'POST',
          headers: authHeaders(),
        });
        if (!r.success) {
          alert(
            r.error === 'no embed — приватное, удалённое или 18+'
              ? 'Видео нельзя добавить: у него нет плеера (приватное, удалённое или 18+). Отклони его.'
              : 'Не распозналось'
          );
        }
        loadSuggest();
        loadStats();
      };
      const no = document.createElement('button');
      no.textContent = 'Отклонить';
      no.className = 'danger';
      no.onclick = async () => {
        await fetch(`/api/suggest/${i}`, {
          method: 'DELETE',
          headers: authHeaders(),
        });
        loadSuggest();
      };
      acts.appendChild(ok);
      acts.appendChild(no);
      box.appendChild(row);
    }
    if (!box.children.length) {
      box.innerHTML = '<p class="muted">Предложений нет.</p>';
    }
  } catch {}
}

const _boot2 = boot;
boot = async function () {
  await _boot2();
  loadSuggest();
};

if (token) boot();

function pickCookiesFile(input) {
  const file = input.files[0];
  if (!file) return;
  const reader = new FileReader();
  reader.onload = (e) => {
    $('sVkCookies').value = e.target.result;
    input.value = '';
  };
  reader.readAsText(file);
}
