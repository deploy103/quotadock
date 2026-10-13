import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { accounts, origin, observations } from './cloud.mjs';
import { collectAccounts, listAccounts, validateBindings } from './collector.mjs';
import { snapshotFromRows } from './snapshot.mjs';
const a = { id: 'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa', provider: 'codex' };
const b = { id: 'bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb', provider: 'codex' };
test('cloud boundary accepts bounded independent slots but rejects unsafe origins and unsupported Gemini mapping', () => {
  for (const url of ['http://example.com', 'https://user:pass@example.com', 'https://example.com/path', 'https://example.com?token=secret']) assert.throws(() => origin(url));
  assert.equal(origin('https://example.com'), 'https://example.com');
  assert.deepEqual(accounts([a, b]), [a, b]);
  assert.throws(() => accounts([a, a]));
  assert.throws(() => accounts([a, { ...a, id: a.id.toUpperCase() }]));
  assert.throws(() => accounts([a, b].map(s => ({ ...s, provider: 'gemini' }))));
  assert.throws(() => observations([a, b], snapshotFromRows([])));
});
test('cloud uploads only whitelist fields and preserves source timestamp/no-data', () => {
  const stamp = '2026-10-13T12:00:00.000Z';
  const snapshot = snapshotFromRows([{ provider: 'codex', email: 'SECRET', usage: { updatedAt: stamp, identity: { loginMethod: 'ChatGPT Pro', token: 'SECRET' }, primary: { usedPercent: 20 } } }]);
  const [o] = observations([a], snapshot);
  assert.equal(o.observedAt, stamp); assert.equal(o.windows[0].remainingPercent, 80);
  assert.equal(JSON.stringify(o).includes('SECRET'), false); assert.equal(Object.hasOwn(o, 'message'), false);
  const [missing] = observations([a], snapshotFromRows([]));
  assert.equal(missing.observedAt, null); assert.equal(missing.state, 'unavailable');
});

test('independent local accounts use durable keys, not order or ambient credentials, and never upload identity', async t => {
  const dir = await mkdtemp(join(tmpdir(), 'quotadock-accounts-'));
  t.after(() => rm(dir, { recursive: true, force: true }));
  const binary = join(dir, 'codexbar');
  const rows = [
    { provider: 'codex', cacheAccountKey: 'codex:workspace:two:email:private@example.com', account: 'SECRET', usage: { updatedAt: '2026-10-13T12:01:02Z', loginMethod: 'ChatGPT Pro', primary: { usedPercent: 87 } } },
    { provider: 'codex', cacheAccountKey: 'codex:stored:one', account: 'SECRET', usage: { updatedAt: '2026-10-13T12:03:04Z', loginMethod: 'Free', primary: { usedPercent: 16 } } },
  ];
  const writeCLI = async value => writeFile(binary, `#!${process.execPath}\nconst selected = process.argv.includes('--all-accounts') && process.argv[process.argv.indexOf('--source') + 1] === 'oauth';\nprocess.stdout.write(JSON.stringify(selected ? ${JSON.stringify(value)} : [{provider:'codex',usage:{primary:{usedPercent:1}}}]));\nprocess.exitCode=1;\n`, { mode: 0o700 });
  await writeCLI(rows);
  const fingerprint = key => createHash('sha256').update(`codex\0${key}`).digest('hex');
  const bindings = {
    [a.id]: { provider: 'codex', fingerprint: fingerprint(rows[1].cacheAccountKey), source: 'oauth' },
    [b.id]: { provider: 'codex', fingerprint: fingerprint(rows[0].cacheAccountKey), source: 'oauth' },
  };
  const listed = await listAccounts('codex', 'oauth', { binary });
  assert.deepEqual(listed, [bindings[b.id].fingerprint, bindings[a.id].fingerprint]);
  const result = observations([a, b], await collectAccounts([a, b], bindings, { binary }));
  assert.deepEqual(result.map(o => o.windows[0].remainingPercent), [84, 13]);
  assert.deepEqual(result.map(o => o.observedAt), ['2026-10-13T12:03:04.000Z', '2026-10-13T12:01:02.000Z']);
  assert.deepEqual(result.map(o => o.plan), ['Free', 'ChatGPT Pro']);
  assert.doesNotMatch(JSON.stringify(result), /SECRET|private@example|fingerprint|cacheAccountKey|codex:stored|codex:workspace/);
  assert.throws(() => validateBindings([a, b], {}));
  assert.throws(() => validateBindings([a, b], { ...bindings, [b.id]: bindings[a.id] }));
  assert.throws(() => validateBindings([a], { [a.id]: { ...bindings[a.id], source: 'cli' } }));
  assert.throws(() => validateBindings([a], { [b.id]: bindings[b.id] }));
  await assert.rejects(listAccounts('gemini', 'oauth', { binary }));
  await writeCLI([rows[1], rows[1]]);
  assert.deepEqual(await listAccounts('codex', 'oauth', { binary }), []);
  const failed = observations([a, b], await collectAccounts([a, b], bindings, { binary }));
  assert.deepEqual(failed.map(o => [o.state, o.observedAt, o.windows]), [['error', null, []], ['error', null, []]]);
});
