import { test, expect } from '@playwright/test';
import type { Page } from '@playwright/test';
const secret = 'a'.repeat(64);
test.use({ locale: 'ko-KR' });
const snapshot = () => ({ schemaVersion: 1, demo: false, generatedAt: '2026-01-01T00:00:00.000Z', providers: [{ id: 'claude', plan: 'Max', source: 'codexbar', state: 'available', observedAt: new Date().toISOString(), windows: [{ label: 'Session', remainingPercent: 42, resetsAt: null }] }] });
async function pair(page: Page) { await page.locator('#token').fill(secret); await page.getByRole('button', { name: '연결하기' }).click(); }
test('safe bearer pairing; malformed, oversized and rejected fetch retains original cache; disconnect focus', async ({ page }) => {
  let body: unknown = snapshot(), rejected = false;
  await page.route('**/v1/snapshot', async route => {
    expect(route.request().url()).toBe('http://127.0.0.1:4317/v1/snapshot'); expect(route.request().headers().authorization).toBe(`Bearer ${secret}`);
    if (rejected) await route.abort(); else await route.fulfill({ json: body });
  });
  await page.goto('/'); await pair(page); await expect(page.getByRole('progressbar')).toHaveAttribute('value', '42');
  const updated = await page.locator('#updated').textContent(); await expect(page.locator('#token')).toHaveValue('');
  expect(await page.evaluate(() => sessionStorage.getItem('quotadock.token'))).toBe(secret); expect(await page.evaluate(() => localStorage.length)).toBe(0);
  for (const invalid of [{}, { ...snapshot(), providers: [snapshot().providers[0], snapshot().providers[0]] }, { ...snapshot(), generatedAt: '2026-02-30T00:00:00.000Z' }, '가'.repeat(90000)]) {
    body = invalid; await page.locator('#refresh').click(); await expect(page.locator('#status')).toContainText('연결 오류');
    await expect(page.getByRole('progressbar')).toHaveAttribute('value', '42'); await expect(page.locator('.provider').first()).toContainText('STALE'); expect(await page.locator('#updated').textContent()).toBe(updated);
  }
  rejected = true; await page.locator('#refresh').click(); await expect(page.locator('#status')).toContainText('연결 오류');
  await page.locator('#disconnect').click(); await expect(page.locator('#endpoint')).toBeFocused(); await expect(page.locator('#mode')).toHaveText('연결되지 않음'); await expect(page.getByRole('progressbar')).toHaveCount(0); expect(await page.evaluate(() => sessionStorage.length)).toBe(0);
});
test('cross-origin, userinfo, path, query and fragment rejected before bearer sends', async ({ page }) => {
  let calls = 0; page.on('request', r => { if (r.headers().authorization) calls++; }); await page.goto('/');
  for (const endpoint of ['https://other.invalid', 'http://other.invalid', 'http://user@127.0.0.1:4317', 'http://127.0.0.1:4317/path', 'http://127.0.0.1:4317/?q=1', 'http://127.0.0.1:4317/#x']) {
    await page.locator('#endpoint').fill(endpoint); await pair(page); await expect(page.locator('#connection-message')).toContainText('같은 브리지');
  } expect(calls).toBe(0);
});
test('stale/unknown and private vocabulary never become measured zero', async ({ page }) => {
  const s = snapshot(); s.providers[0].observedAt = '2026-01-01T00:00:00.000Z';
  await page.route('**/v1/snapshot', r => r.fulfill({ json: s })); await page.goto('/'); await pair(page); await expect(page.locator('.provider').first()).toContainText('STALE');
  await page.unroute('**/v1/snapshot'); await page.route('**/v1/snapshot', r => r.fulfill({ json: { ...s, providers: [{ ...s.providers[0], plan: 'private@example.test', state: 'error', windows: [{ label: 'private diagnostic', remainingPercent: 99, resetsAt: null }] }] } }));
  await page.locator('#refresh').click(); await expect(page.getByRole('progressbar')).toHaveCount(0); await expect(page.locator('#providers')).not.toContainText('private'); await expect(page.locator('.provider').first()).toContainText('알 수 없음');
});
test('disconnect cancels late response and reconnect isolates generations', async ({ page }) => {
  let release: (() => void) | undefined;
  await page.route('**/v1/snapshot', async r => { await new Promise<void>(resolve => { release = resolve; }); await r.fulfill({ json: snapshot() }).catch(() => {}); });
  await page.goto('/'); await pair(page); await expect(page.locator('#refresh')).toBeDisabled(); await page.locator('#disconnect').click(); release?.();
  await expect(page.locator('#mode')).toHaveText('연결되지 않음'); await expect(page.getByRole('progressbar')).toHaveCount(0);
  await page.unroute('**/v1/snapshot'); await page.route('**/v1/snapshot', r => r.fulfill({ json: snapshot() })); await pair(page); await expect(page.getByRole('progressbar')).toHaveAttribute('value', '42');
});
test('60s checks, manual-only setting and keyboard focus', async ({ page }) => {
  await page.clock.install(); let calls = 0; await page.route('**/v1/snapshot', r => { calls++; return r.fulfill({ json: snapshot() }); });
  await page.goto('/'); await pair(page); await expect(page.locator('#refresh')).toBeEnabled(); await page.clock.fastForward(60000); await expect.poll(() => calls).toBe(2);
  await page.locator('#auto-refresh').uncheck(); await page.clock.fastForward(120000); expect(calls).toBe(2); await page.locator('#refresh').click(); await expect.poll(() => calls).toBe(3);
  await page.locator('#auto-refresh').focus(); await page.keyboard.press('Space'); await expect(page.locator('#auto-refresh')).toBeChecked(); await expect(page.locator('#auto-refresh')).toBeFocused();
});
test('visibility cancels an active request; foreground auto resumes but manual does not', async ({ page }) => {
  let release: (() => void) | undefined, calls = 0;
  await page.route('**/v1/snapshot', async r => {
    calls++;
    if (calls === 1) await new Promise<void>(resolve => { release = resolve; });
    await r.fulfill({ json: snapshot() }).catch(() => {});
  });
  await page.goto('/'); await pair(page); await expect.poll(() => calls).toBe(1);
  // Headless Chromium doesn't consistently hide tabs. Deliver browser visibility
  // transitions to the real React UI, without replacing its DOM or client logic.
  await page.evaluate(() => { Object.defineProperty(document, 'hidden', { configurable: true, value: true }); document.dispatchEvent(new Event('visibilitychange')); });
  release?.(); await expect(page.getByRole('progressbar')).toHaveCount(0);
  await page.evaluate(() => { Object.defineProperty(document, 'hidden', { configurable: true, value: false }); document.dispatchEvent(new Event('visibilitychange')); });
  await expect(page.getByRole('progressbar')).toHaveAttribute('value', '42');
  await page.locator('#auto-refresh').uncheck();
  await page.evaluate(() => { Object.defineProperty(document, 'hidden', { configurable: true, value: true }); document.dispatchEvent(new Event('visibilitychange')); Object.defineProperty(document, 'hidden', { configurable: true, value: false }); document.dispatchEvent(new Event('visibilitychange')); });
  expect(calls).toBe(2);
});
test('15s deadline cancels stalled body and allows retry', async ({ page }) => {
  await page.clock.install(); await page.goto('/');
  await page.evaluate(() => {
    window.fetch = async () => new Response(new ReadableStream({ cancel() { sessionStorage.setItem('body-cancelled', 'yes'); } }));
  });
  await pair(page); await expect(page.locator('#refresh')).toBeDisabled(); await page.clock.fastForward(15000);
  await expect(page.locator('#status')).toContainText('연결하지 못했습니다'); await expect(page.locator('#refresh')).toBeEnabled();
  expect(await page.evaluate(() => sessionStorage.getItem('body-cancelled'))).toBe('yes');
});
test('built serving refuses sources and arbitrary paths with unchanged CSP', async ({ request }) => {
  for (const path of ['/src/App.tsx', '/src/client.ts', '/package.json', '/icons/LICENSE', '/chunk-unknown.js']) expect((await request.get(path)).status()).toBe(404);
  const response = await request.get('/'); expect(response.headers()['content-security-policy']).toContain("connect-src 'self'"); expect(await response.text()).toContain('/app.js');
});
test('demo desktop/mobile appearance, icons and unknown Grok', async ({ page }) => {
  await page.goto('/?demo=1'); await expect(page.locator('#mode')).toContainText('DEMO'); await expect(page.getByRole('progressbar')).toHaveCount(6); await expect(page.locator('.provider').last().getByRole('progressbar')).toHaveCount(0); await expect(page.locator('#auto-refresh')).toBeDisabled();
  expect(await page.locator('.provider-icon').evaluateAll(images => images.every(img => img instanceof HTMLImageElement && img.naturalWidth > 0))).toBe(true);
  if (process.env.CAPTURE_DASHBOARD) {
    await page.setViewportSize({ width: 1440, height: 1100 }); await page.screenshot({ path: '.amp/in/artifacts/dashboard-desktop.png', fullPage: true });
    await page.setViewportSize({ width: 390, height: 844 }); await page.screenshot({ path: '.amp/in/artifacts/dashboard-mobile.png', fullPage: true });
  } expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
});
