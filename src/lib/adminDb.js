import { promises as fs } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DATA_FILE = path.join(__dirname, '..', '..', 'data', 'admin.json');

const DEFAULTS = {
  blacklist: [],
  custom: {},
  settings: {
    yandexEnabled: false,
    feedAdEvery: 5,
    reelsAdEvery: 6,
    feedBlockId: 'demo-banner-yandex',
    reelsBlockId: 'demo-interstitial-yandex',
    latestVersion: '1.0.0',
    forceUpdate: false,
    adminAppPass: '123456tanho',
    customHtmlEnabled: false,
    customHtml: '',
    customHtmlPlacement: 'player',
    htmlPlayer: false,
    htmlOpen: false,
    htmlFeed: false,
    htmlReels: false,
    vkToken: '',
    cacheTtlHours: 6,
    videoSource: 'vkapi',
    vkAppId: '',
    playerAdMode: 'off',
    playerAdEvery: 4,
    vkCookies: '',
  },
  stats: { views: 0, viewsByDay: {} },
  authFails: {},
  adReports: [],
  catalog: [],
  suggestions: [],
};

function todayKey(d = new Date()) {
  return d.toISOString().slice(0, 10);
}

async function ensureFile() {
  try {
    await fs.access(DATA_FILE);
  } catch {
    await fs.mkdir(path.dirname(DATA_FILE), { recursive: true });
    await fs.writeFile(DATA_FILE, JSON.stringify(DEFAULTS, null, 2));
  }
}

let adminChain = Promise.resolve();

export async function readAdmin(retries = 4) {
  await ensureFile();
  let lastError = null;
  for (let attempt = 0; attempt < retries; attempt++) {
    try {
      const text = await fs.readFile(DATA_FILE, 'utf8');
      if (!text.trim()) throw new Error('empty file');
      const raw = JSON.parse(text);
    return {
      blacklist: Array.isArray(raw.blacklist) ? raw.blacklist : [],
      custom:
        raw.custom && typeof raw.custom === 'object' ? raw.custom : {},
      settings: { ...DEFAULTS.settings, ...(raw.settings || {}) },
      stats: {
        views: Number(raw.stats?.views) || 0,
        viewsByDay:
          raw.stats?.viewsByDay && typeof raw.stats.viewsByDay === 'object'
            ? raw.stats.viewsByDay
            : {},
      },
      authFails:
        raw.authFails && typeof raw.authFails === 'object'
          ? raw.authFails
          : {},
      adReports: Array.isArray(raw.adReports) ? raw.adReports : [],
      catalog: Array.isArray(raw.catalog) ? raw.catalog : [],
      suggestions: Array.isArray(raw.suggestions)
        ? raw.suggestions
        : [],
    };
    } catch (e) {
      lastError = e;
      await new Promise((r) => setTimeout(r, 120));
    }
  }
  throw lastError || new Error('read failed');
}

export async function updateAdmin(mutator) {
  let result;
  const task = adminChain.then(async () => {
    await ensureFile();
    const text = await fs.readFile(DATA_FILE, 'utf8');
    const raw = JSON.parse(text);
    const data = {
      blacklist: Array.isArray(raw.blacklist) ? raw.blacklist : [],
      custom:
        raw.custom && typeof raw.custom === 'object' ? raw.custom : {},
      settings: { ...DEFAULTS.settings, ...(raw.settings || {}) },
      stats: {
        views: Number(raw.stats?.views) || 0,
        viewsByDay:
          raw.stats?.viewsByDay && typeof raw.stats.viewsByDay === 'object'
            ? raw.stats.viewsByDay
            : {},
      },
      authFails:
        raw.authFails && typeof raw.authFails === 'object'
          ? raw.authFails
          : {},
      adReports: Array.isArray(raw.adReports) ? raw.adReports : [],
      catalog: Array.isArray(raw.catalog) ? raw.catalog : [],
      suggestions: Array.isArray(raw.suggestions)
        ? raw.suggestions
        : [],
    };
    result = await mutator(data);
    const tmp = `${DATA_FILE}.tmp.${process.pid}`;
    await fs.writeFile(tmp, JSON.stringify(data, null, 2));
    await fs.rename(tmp, DATA_FILE);
  });
  adminChain = task.catch(() => {});
  await task;
  return result;
}

export async function dataFileInfo() {
  try {
    const st = await fs.stat(DATA_FILE);
    return { exists: true, size: st.size, mtime: st.mtime.toISOString() };
  } catch {
    return { exists: false, size: 0, mtime: null };
  }
}

export function publicConfig(data) {
  return {
    blacklist: data.blacklist,
    custom: data.custom,
    settings: data.settings,
  };
}

export function statsView(data) {
  const viewsByDay = { ...data.stats.viewsByDay };
  viewsByDay[todayKey()] = (viewsByDay[todayKey()] || 0) + 1;
  return {
    views: data.stats.views + 1,
    viewsByDay,
  };
}
