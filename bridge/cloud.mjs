import { request } from 'node:https';
import { mkdir, open, lstat, rename, unlink } from 'node:fs/promises';
import { constants } from 'node:fs';
import { homedir } from 'node:os';
import { dirname } from 'node:path';
import { pathToFileURL } from 'node:url';
import { randomUUID } from 'node:crypto';
import { collectAccounts, listAccounts, validateBindings } from './collector.mjs';
import { providers } from './snapshot.mjs';

const credential = /^[A-Za-z0-9_-]{43}$/;
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const wait = ms => new Promise(resolve => setTimeout(resolve, ms));
export function origin(value) {
  const u = new URL(value);
  if (u.protocol !== 'https:' || u.username || u.password || u.search || u.hash || u.pathname !== '/') throw Error('configuration');
  return u.origin;
}
export function accounts(value) {
  if (!Array.isArray(value) || !value.length || value.length > 50 || value.some(a => !uuid.test(a?.id) || !Object.hasOwn(providers, a?.provider)) || value.filter(a => a.provider === 'gemini').length > 1 || new Set(value.map(a => a.id.toLowerCase())).size !== value.length) throw Error('unsupported_slots');
  return value.map(({ id, provider }) => ({ id: id.toLowerCase(), provider }));
}
export function api(base, path, token, body) {
  return new Promise((resolve, reject) => {
    const req = request(new URL(path, origin(base)), { method: body === undefined ? 'GET' : 'POST', headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), ...(body === undefined ? {} : { 'content-type': 'application/json' }) } }, res => {
      let size = 0; const chunks = [];
      res.on('data', chunk => { size += chunk.length; if (size > 65536) req.destroy(Error('response')); else chunks.push(chunk); });
      res.on('error', reject);
      res.on('end', () => {
        try {
          if (res.statusCode < 200 || res.statusCode >= 300) throw Error(res.statusCode === 401 ? 'revoked' : res.statusCode === 403 ? 'forbidden' : 'service');
          resolve(JSON.parse(Buffer.concat(chunks).toString('utf8')));
        } catch (e) { reject(e); }
      });
    });
    // Absolute deadline, not an inactivity timeout; redirects are never followed.
    const timer = setTimeout(() => req.destroy(Error('timeout')), 15000);
    req.on('close', () => clearTimeout(timer)); req.on('error', reject);
    req.end(body === undefined ? undefined : JSON.stringify(body));
  });
}
async function privateDirectory(file) {
  await mkdir(dirname(file), { recursive: true, mode: 0o700 });
  const s = await lstat(dirname(file));
  if (!s.isDirectory() || s.isSymbolicLink() || s.uid !== process.getuid?.() || (s.mode & 0o077)) throw Error('configuration');
}
async function save(file, data) {
  await privateDirectory(file);
  const fd = await open(file, 'wx', 0o600);
  try { await fd.writeFile(JSON.stringify(data)); await fd.sync(); } finally { await fd.close(); }
}
async function loadJSON(file) {
  await privateDirectory(file);
  const fd = await open(file, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const s = await fd.stat();
    if (!s.isFile() || s.uid !== process.getuid?.() || (s.mode & 0o077) || s.size > 16384) throw Error('configuration');
    return JSON.parse(await fd.readFile('utf8'));
  } finally { await fd.close(); }
}
async function load(file) {
  const c = await loadJSON(file);
  if (!credential.test(c.collectorToken) || !Number.isFinite(c.expiresAt) || c.expiresAt <= Date.now()) throw Error('revoked');
  return { base: origin(c.base), collectorToken: c.collectorToken, accounts: accounts(c.accounts) };
}
async function loadBindings(file) {
  try { return await loadJSON(file); } catch (e) { if (e.code === 'ENOENT') return {}; throw e; }
}
export function observations(slots, snapshot) {
  return accounts(slots).map(a => {
    if (!Array.isArray(snapshot) && slots.filter(s => s.provider === a.provider).length > 1) throw Error('unsupported_mapping');
    const candidates = Array.isArray(snapshot) ? snapshot.filter(p => p.accountId === a.id && p.id === a.provider) : snapshot.providers.filter(p => p.id === a.provider);
    if (candidates.length !== 1) throw Error('response');
    const [p] = candidates;
    return { accountId: a.id, provider: a.provider, plan: p.plan, state: p.state, source: 'codexbar', observedAt: p.observedAt, windows: p.windows.map(w => ({ id: w.id, label: w.label, remainingPercent: w.remainingPercent, resetsAt: w.resetsAt })) };
  });
}
export async function runOnce(c, { automatic = false } = {}) {
  validateBindings(c.accounts, c.bindings ?? {});
  let { job } = await api(c.base, '/v2/collector/jobs/next', c.collectorToken);
  if (!job && automatic) {
    try {
      const result = await api(c.base, '/v2/collector/refresh', c.collectorToken, { accountIds: c.accounts.map(a => a.id), mode: 'auto', idempotencyKey: randomUUID() });
      if (result.status === 'pending') ({ job } = await api(c.base, '/v2/collector/jobs/next', c.collectorToken));
    } catch (e) { if (e.message === 'forbidden') return; throw e; }
  }
  if (!job) return;
  const slots = accounts(job.accounts);
  if (!uuid.test(job.id) || slots.some(a => !c.accounts.some(g => g.id === a.id && g.provider === a.provider)) || !Array.isArray(job.accountIds) || job.accountIds.length !== slots.length || job.accountIds.some(id => !slots.some(a => a.id === id))) throw Error('response');
  const issued = Date.parse(job.createdAt), expires = Date.parse(job.expiresAt);
  if (!Number.isFinite(issued) || !Number.isFinite(expires) || issued > Date.now() + 5000) throw Error('response');
  await wait(Math.max(0, Math.floor(issued / 1000) * 1000 + 1001 - Date.now()));
  if (Date.now() >= expires) return;
  const bindings = Object.fromEntries(slots.filter(a => c.bindings?.[a.id]).map(a => [a.id, c.bindings[a.id]]));
  const snapshot = await collectAccounts(slots, bindings, { binary: process.env.QUOTADOCK_CODEXBAR_BIN || 'codexbar' });
  if (Date.now() >= expires) return;
  await api(c.base, `/v2/collector/refresh/${job.id}/complete`, c.collectorToken, { observations: observations(slots, snapshot) });
}
async function main() {
  const [command, ...args] = process.argv.slice(2);
  const [base] = args;
  const file = `${homedir()}/.config/quotadock-cloud/collector.json`;
  const mappingFile = `${dirname(file)}/accounts.json`;
  if (command === 'accounts') {
    if (args.length < 1 || args.length > 2) throw Error('configuration');
    const fingerprints = await listAccounts(args[0], args[1] ?? 'oauth', { binary: process.env.QUOTADOCK_CODEXBAR_BIN || 'codexbar' });
    process.stdout.write(`${JSON.stringify({ provider: args[0], source: args[1] ?? 'oauth', fingerprints })}\n`); return;
  }
  if (command === 'map') {
    if (args.length < 3 || args.length > 4) throw Error('configuration');
    const [inputID, provider, fingerprint, source = 'oauth'] = args;
    if (!uuid.test(inputID)) throw Error('configuration');
    const id = inputID.toLowerCase();
    const c = await load(file);
    const bindings = await loadBindings(mappingFile);
    const next = { ...bindings, [id]: { provider, fingerprint, source } };
    // Partial configuration is allowed while adding mappings; run validates all slots.
    validateBindings(c.accounts.filter(a => Object.hasOwn(next, a.id)), next);
    const temporary = `${mappingFile}.${randomUUID()}.tmp`;
    try { await save(temporary, next); await rename(temporary, mappingFile); }
    finally { await unlink(temporary).catch(e => { if (e.code !== 'ENOENT') throw e; }); }
    process.stdout.write('Local account mapping saved. Restart the collector after configuring every duplicate-provider slot.\n'); return;
  }
  if (!['pair', 'run', 'once'].includes(command) || args.length !== (command === 'pair' ? 1 : 0)) throw Error('configuration');
  if (command === 'pair') {
    const trusted = origin(base);
    // Never redeem a grant if it cannot be saved without overwriting an existing one.
    await privateDirectory(file);
    try { await lstat(file); throw Error('configuration'); } catch (e) { if (e.code !== 'ENOENT') throw e; }
    const p = await api(trusted, '/v2/collector/pair', null, {});
    if (!/^[A-F0-9]{8}$/.test(p.code) || !credential.test(p.pollingToken) || p.expiresIn !== 300) throw Error('response');
    process.stdout.write(`Approve code ${p.code} on your phone. Confirm the selected account slots explicitly.\n`);
    const deadline = Date.now() + 300000;
    while (Date.now() < deadline) {
      await wait(3000);
      const r = await api(trusted, '/v2/collector/pair', p.pollingToken);
      if (r.status === 'pending') continue;
      if (r.status !== 'approved' || !credential.test(r.collectorToken) || r.expiresIn !== 2592000) throw Error('response');
      await save(file, { base: trusted, collectorToken: r.collectorToken, expiresAt: Date.now() + r.expiresIn * 1000, accounts: accounts(r.accounts) });
      process.stdout.write('Collector paired. Provider credentials remain local.\n'); return;
    }
    throw Error('timeout');
  }
  const c = await load(file);
  c.bindings = await loadBindings(mappingFile);
  validateBindings(c.accounts, c.bindings);
  let nextAutoAt = 0;
  do {
    const automatic = command === 'run' && Date.now() >= nextAutoAt;
    if (automatic) nextAutoAt = Date.now() + 20 * 60000;
    try { await runOnce(c, { automatic }); }
    catch (e) { if (e.message === 'revoked' || command === 'once') throw e; process.stderr.write('QuotaDock cloud: temporary failure; retrying safely.\n'); }
    if (command === 'run') await wait(20000);
  } while (command === 'run');
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main().catch(() => {
  process.stderr.write('QuotaDock cloud: operation failed. Check network, private configuration, supported slots, and phone grant; re-pair if revoked or expired.\n'); process.exitCode = 1;
});
