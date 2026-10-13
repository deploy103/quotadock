import { test } from 'node:test';
import assert from 'node:assert/strict';
import { accounts, origin, observations } from './cloud.mjs';
import { snapshotFromRows } from './snapshot.mjs';
const a = { id: 'aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa', provider: 'codex' };
test('cloud boundary rejects unsafe origins and ambiguous slots', () => {
  for (const url of ['http://example.com', 'https://user:pass@example.com', 'https://example.com/path', 'https://example.com?token=secret']) assert.throws(() => origin(url));
  assert.equal(origin('https://example.com'), 'https://example.com');
  assert.throws(() => accounts([a, { ...a, id: 'bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb' }]));
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
