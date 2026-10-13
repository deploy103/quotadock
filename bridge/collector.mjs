import { spawn } from 'node:child_process';
import { providers, snapshotFromRows } from './snapshot.mjs';

// Never run a shell or accept provider commands over HTTP. Upstream logs stay private.
function query(binary, id, timeoutMs) {
  return new Promise(resolve => {
    let chunks = [], size = 0, completed = false;
    const child = spawn(binary, ['usage', '--provider', id, '--format', 'json', '--json-only'], { stdio: ['ignore', 'pipe', 'ignore'], windowsHide: true, detached: process.platform !== 'win32' });
    const failed = () => [{ provider: id, error: { kind: 'provider' } }];
    const stop = () => {
      try { if (process.platform !== 'win32') process.kill(-child.pid, 'SIGKILL'); else child.kill('SIGKILL'); } catch {}
    };
    const finish = rows => { if (!completed) { completed = true; clearTimeout(timer); resolve(rows); } };
    const timer = setTimeout(() => { stop(); finish(failed()); }, timeoutMs);
    child.on('error', () => finish(failed()));
    child.stdout.on('data', chunk => {
      size += chunk.length;
      if (size > 1024 * 1024) { stop(); finish(failed()); } else chunks.push(chunk);
    });
    child.on('close', () => {
      if (completed) return;
      try {
        // Some providers fail independently and still emit usable JSON with nonzero exit.
        const rows = JSON.parse(Buffer.concat(chunks).toString('utf8'));
        finish(Array.isArray(rows) && rows.some(row => row?.provider === id) ? rows.filter(row => row?.provider === id) : failed());
      } catch { finish(failed()); }
    });
  });
}

export async function collect({ binary = 'codexbar', timeoutMs = 12000 } = {}) {
  const rows = (await Promise.all(Object.keys(providers).map(id => query(binary, id, timeoutMs)))).flat();
  return snapshotFromRows(rows);
}

export function cachedCollector(load, { ttlMs = 60000, now = Date.now } = {}) {
  let last = null, loadedAt = 0, pending = null;
  return async () => {
    if (last && now() - loadedAt < ttlMs) return last;
    if (!pending) pending = Promise.resolve().then(load).then(snapshot => { last = snapshot; loadedAt = now(); return snapshot; }).finally(() => { pending = null; });
    return pending;
  };
}
