const ring = [];
const MAX = 30;

export function logSync(entry) {
  ring.unshift({
    ts: new Date().toISOString(),
    source: String(entry.source || '').slice(0, 80),
    existing: Number(entry.existing) || 0,
    fetched: Number(entry.fetched) || 0,
    added: Number(entry.added) || 0,
    updated: Number(entry.updated) || 0,
    final: Number(entry.final) || 0,
    ok: entry.ok !== false,
    note: String(entry.note || '').slice(0, 120),
  });
  if (ring.length > MAX) ring.length = MAX;
}

export function lastSyncs() {
  return ring.slice();
}
