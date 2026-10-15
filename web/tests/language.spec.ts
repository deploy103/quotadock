import { test, expect } from '@playwright/test';
test.use({ locale: 'en-US' });
for (const width of [390, 1440]) test(`language preserves pairing and readings at ${width}`, async ({ page }) => {
  await page.setViewportSize({ width, height: 1000 });
  let calls = 0, reject = false;
  const secret = 'a'.repeat(64);
  const upstreamPlan = 'Max';
  const upstreamWindow = 'Weekly';
  await page.route('**/v1/snapshot', route => {
    calls++; expect(route.request().headers().authorization).toBe(`Bearer ${secret}`);
    return reject ? route.abort() : route.fulfill({ json: { schemaVersion: 1, demo: false, generatedAt: '2026-01-01T00:00:00.000Z', providers: [{ id: 'claude', plan: upstreamPlan, source: 'codexbar', state: 'available', observedAt: '2026-01-01T00:00:00.000Z', windows: [{ label: 'Session', remainingPercent: 42.5, resetsAt: null }, { label: upstreamWindow, remainingPercent: null, resetsAt: null }] }] } });
  });
  await page.goto('/'); const language = page.locator('header select');
  await expect(page.locator('html')).toHaveAttribute('lang', 'en');
  await expect(page.getByRole('heading', { name: 'Connecting for the first time?' })).toBeVisible();
  if (process.env.CAPTURE_DASHBOARD) await page.screenshot({ path: `.amp/in/artifacts/dashboard-en-guide-${width}.png`, fullPage: true });
  await page.locator('#token').fill(secret); await language.focus(); await language.selectOption('ko'); await expect(language).toBeFocused();
  await expect(page.locator('#token')).toHaveValue(secret); expect(calls).toBe(0);
  await page.getByRole('button', { name: '연결 안내 닫기' }).focus(); await page.keyboard.press('Enter');
  await expect(page.locator('#endpoint')).toBeFocused();
  await page.getByRole('button', { name: '연결하기' }).click();
  await expect(page.getByRole('progressbar')).toHaveAttribute('value', '42.5');
  await page.locator('#auto-refresh').uncheck(); await language.selectOption('en');
  await expect(page.locator('.plan').first()).toHaveText(`Plan · ${upstreamPlan}`);
  await expect(page.locator('.window-heading span').nth(1)).toHaveText(upstreamWindow);
  await expect(page.locator('#disconnect')).toBeVisible();
  expect(await page.evaluate(() => sessionStorage.getItem('quotadock.token'))).toBe(secret);
  await expect(page.getByRole('progressbar')).toHaveAttribute('aria-label', 'Claude Session Remaining quota');
  await expect(page.locator('#updated')).toContainText('Jan');
  expect(calls).toBe(1); await expect(page.locator('#auto-refresh')).not.toBeChecked();
  reject = true; await page.locator('#refresh').click(); await expect(page.locator('#status')).toContainText('Connection error');
  await language.selectOption('ko'); await expect(page.locator('#status')).toContainText('연결 오류');
  await expect(page.locator('.plan').first()).toHaveText(`플랜 · ${upstreamPlan}`);
  await expect(page.locator('.window-heading span').nth(1)).toHaveText('주간');
  await expect(page.locator('#disconnect')).toBeVisible();
  expect(await page.evaluate(() => sessionStorage.getItem('quotadock.token'))).toBe(secret);
  await expect(page.getByRole('progressbar')).toHaveAttribute('value', '42.5'); expect(calls).toBe(2);
  await expect(page.locator('body')).not.toContainText(secret);
  if (process.env.CAPTURE_DASHBOARD) await page.screenshot({ path: `.amp/in/artifacts/dashboard-ko-error-${width}.png`, fullPage: true });
  await page.reload(); await expect(page.locator('html')).toHaveAttribute('lang', 'ko'); await expect(page.locator('#guide-title')).toHaveCount(0);
  await page.goto('/?demo=1'); const before = calls;
  const values = await page.getByRole('progressbar').evaluateAll(bars => bars.map(bar => (bar as HTMLProgressElement).value));
  await language.selectOption('en');
  expect(await page.getByRole('progressbar').evaluateAll(bars => bars.map(bar => (bar as HTMLProgressElement).value))).toEqual(values);
  const untranslated = await page.evaluate(() => [...document.querySelectorAll('body *')].flatMap(element => [...element.childNodes].filter(node => node.nodeType === Node.TEXT_NODE && element.tagName !== 'OPTION' && /[가-힣]/.test(node.textContent || '')).map(node => node.textContent)));
  expect(untranslated).toEqual([]);
  expect(calls).toBe(before); await expect(page.locator('#mode')).toContainText('DEMO');
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  if (process.env.CAPTURE_DASHBOARD) await page.screenshot({ path: `.amp/in/artifacts/dashboard-en-demo-${width}.png`, fullPage: true });
  await language.selectOption('system'); await expect(page.locator('html')).toHaveAttribute('lang', 'en');
});
test('display data is not a translation label', async ({ page }) => {
  // Demo readings bypass the privacy allowlist, so exercise the presentation
  // boundary without changing the production snapshot parser.
  const plan = 'Max · 사용량 · 예시 · 알 수 없음';
  const label = 'Custom 사용량 Session 예시';
  await page.route('**/app.js', async route => {
    const response = await route.fetch();
    const body = await response.text();
    expect(body).toContain('plan:"Max"');
    expect(body).toContain('"Session",72,3');
    await route.fulfill({ response, body: body.replace('plan:"Max"', `plan:${JSON.stringify(plan)}`).replace('"Session",72,3', `${JSON.stringify(label)},72,3`) });
  });
  let requests = 0;
  page.on('request', () => requests++);
  await page.goto('/?demo=1');
  await expect(page.getByRole('progressbar')).toHaveCount(6);
  await page.waitForLoadState('networkidle');
  const count = requests;
  for (const language of ['ko', 'en', 'ko', 'en']) {
    await page.locator('header select').selectOption(language);
    await expect(page.locator('.plan').first()).toHaveText(`${language === 'ko' ? '플랜' : 'Plan'} · ${plan}`);
    await expect(page.locator('.window-heading span').first()).toHaveText(label);
    await expect(page.getByRole('progressbar').first()).toHaveAttribute('aria-label', `Claude ${label} ${language === 'ko' ? '남은 사용량' : 'Remaining quota'}`);
    expect(requests).toBe(count);
  }
});
for (const mode of ['invalid', 'blocked']) test(`language fallback with ${mode} storage`, async ({ page }) => {
  await page.addInitScript(mode => {
    if (mode === 'blocked') for (const method of ['getItem', 'setItem', 'removeItem']) Object.defineProperty(Storage.prototype, method, { value() { throw new Error('blocked'); } });
    else localStorage.setItem('quotadock.language', '{invalid}');
  }, mode);
  let bearer = 0; page.on('request', request => { if (request.headers().authorization) bearer++; });
  await page.goto('/?demo=1'); await expect(page.locator('html')).toHaveAttribute('lang', 'en');
  await page.locator('header select').selectOption('ko'); await expect(page.locator('html')).toHaveAttribute('lang', 'ko');
  await page.reload(); await expect(page.locator('html')).toHaveAttribute('lang', 'en'); expect(bearer).toBe(0);
});
test.describe('unsupported system locale', () => {
  test.use({ locale: 'fr-FR' });
  test('defaults to English', async ({ page }) => {
    await page.goto('/?demo=1'); await expect(page.locator('html')).toHaveAttribute('lang', 'en');
    await expect(page.locator('header select')).toHaveValue('system');
  });
});
