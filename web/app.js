'use strict';
(() => {
  const $ = id => document.getElementById(id);
  const names = { claude: 'Claude', codex: 'Codex', gemini: 'Gemini', grok: 'Grok' };
  const demo = new URLSearchParams(location.search).get('demo') === '1';
  let paired = false, last = null, failed = false, busy = false, generation = 0;
  let endpoint = '', token = '';
  const date = value => {
    if (!value || !Number.isFinite(Date.parse(value))) return '알 수 없음';
    return new Intl.DateTimeFormat('ko-KR', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit', timeZoneName: 'short' }).format(new Date(value));
  };
  const node = (tag, text, cls) => { const el = document.createElement(tag); if (text !== undefined) el.textContent = text; if (cls) el.className = cls; return el; };
  const safeEndpoint = url => url.origin === location.origin && !url.username && !url.password && !url.search && !url.hash && ['', '/'].includes(url.pathname) && (url.protocol === 'https:' || url.protocol === 'http:' && ['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname));
  const stale = p => failed || !p.observedAt || !Number.isFinite(Date.parse(p.observedAt)) || Date.now() - Date.parse(p.observedAt) > 900000;
  function render() {
    $('providers').replaceChildren();
    for (const [id, name] of Object.entries(names)) {
      const p = last?.providers.find(p => p.id === id);
      const card = node('article', undefined, 'provider');
      const header = node('div', undefined, 'provider-header');
      const title = node('div', undefined, 'provider-title');
      const icon = node('img', undefined, 'provider-icon'); icon.src = `/icons/${id}.svg`; icon.alt = ''; icon.width = 38; icon.height = 38; title.append(icon);
      const identity = node('div'); identity.append(node('h3', name), node('div', `플랜 · ${p?.plan || '알 수 없음'}`, 'plan')); title.append(identity);
      const old = p?.state === 'available' && stale(p);
      const sample = demo || last?.demo || p?.source === 'demo';
      header.append(title, node('span', sample ? `DEMO${old ? ' · STALE' : ''}` : !p ? '미연결' : p.state !== 'available' ? '확인 불가' : old ? 'STALE' : 'LIVE', old ? 'badge is-stale' : 'badge')); card.append(header);
      if (old) card.className = 'provider is-stale';
      if (id === 'codex') card.append(node('p', 'ChatGPT 플랜의 Codex 허용량 · 전체 ChatGPT 사용량 아님', 'provider-note'));
      if (id === 'gemini') card.append(node('p', '모델 티어별 할당량 · 각 창을 따로 확인하세요', 'provider-note'));
      if (!p || !p.windows.length) card.append(node('p', !p ? '연결 후 남은 사용량을 확인할 수 있어요.' : '사용량을 확인할 수 없습니다. 추정하지 않습니다.', 'unknown'));
      for (const w of p?.windows || []) {
        const row = node('div', undefined, 'window');
        const heading = node('div', undefined, 'window-heading');
        const measured = p.state === 'available' && typeof w.remainingPercent === 'number' && Number.isFinite(w.remainingPercent);
        const amount = measured ? Math.min(100, Math.max(0, w.remainingPercent)) : null;
        heading.append(node('span', w.label), node('strong', amount === null ? '알 수 없음' : `${amount}% 남음`)); row.append(heading);
        if (amount !== null) { const bar = node('progress', undefined, 'track'); bar.max = 100; bar.value = amount; bar.setAttribute('aria-label', `${name} ${w.label} 남은 사용량`); bar.setAttribute('aria-valuemin', '0'); bar.setAttribute('aria-valuemax', '100'); bar.setAttribute('aria-valuenow', String(amount)); row.append(bar); }
        else row.append(node('p', '측정된 사용량 없음 · 추정 막대 없음', 'unknown'));
        row.append(node('p', `리셋 · ${date(w.resetsAt)}`, 'reset')); card.append(row);
      }
      if (p?.state === 'error') card.append(node('p', '제공자 데이터를 가져오지 못했습니다.', 'stale'));
      card.append(node('div', p ? `출처 · ${p.source === 'demo' ? 'DEMO 예시' : 'CodexBar'} / 관측 · ${date(p.observedAt)}${old ? ' · 오래된 데이터' : ''}` : '출처 · 미연결 / 관측 · 없음', 'source'));
      $('providers').append(card);
    }
    $('mode').textContent = demo || last?.demo ? 'DEMO · SAMPLE DATA' : paired ? 'BRIDGE CONNECTED' : 'NOT CONNECTED';
    $('refresh').disabled = busy || (!paired && !demo);
    $('disconnect').hidden = !paired;
    $('updated').textContent = last ? `스냅샷 · ${date(last.generatedAt)}${demo ? ' · 로컬 예시' : ' · 연결 중 60초마다 확인'}` : '아직 받은 데이터가 없습니다.';
  }
  function valid(s) {
    return s && s.schemaVersion === 1 && typeof s.demo === 'boolean' && typeof s.generatedAt === 'string' && Number.isFinite(Date.parse(s.generatedAt)) && Array.isArray(s.providers) && s.providers.every(p => p && Object.hasOwn(names, p.id) && ['available','unavailable','error'].includes(p.state) && ['codexbar','demo'].includes(p.source) && (p.plan === null || typeof p.plan === 'string') && (p.observedAt === null || typeof p.observedAt === 'string') && Array.isArray(p.windows) && p.windows.every(w => w && typeof w.label === 'string' && (w.remainingPercent === null || typeof w.remainingPercent === 'number' && Number.isFinite(w.remainingPercent)) && (w.resetsAt === null || typeof w.resetsAt === 'string')));
  }
  async function refresh() {
    if (busy || !paired) return;
    const version = generation; busy = true; $('status').textContent = '사용량 확인 중…'; render();
    const controller = new AbortController(); const timeout = setTimeout(() => controller.abort(), 15000);
    try {
      const response = await fetch(`${endpoint}/v1/snapshot`, { headers: { Authorization: `Bearer ${token}` }, cache: 'no-store', credentials: 'omit', redirect: 'error', signal: controller.signal });
      if (!response.ok) throw new Error('request');
      const body = await response.text(); if (body.length > 262144) throw new Error('size');
      const snapshot = JSON.parse(body); if (!valid(snapshot)) throw new Error('schema');
      if (version !== generation) return;
      last = snapshot; failed = false; $('status').textContent = snapshot.providers.some(p => p.state === 'available' && stale(p)) ? '오래된 관측 데이터가 있습니다' : '남은 사용량을 확인했어요'; $('connection-message').textContent = '';
    } catch {
      if (version !== generation) return;
      failed = true; $('status').textContent = last ? '연결 오류 · 마지막 데이터 표시 중' : '브리지에 연결하지 못했습니다';
      $('connection-message').textContent = '주소, 토큰, HTTPS 인증서와 브리지의 접근 허용 설정을 확인해 주세요. 자동으로 다시 확인합니다.';
    } finally { clearTimeout(timeout); if (version === generation) { busy = false; render(); } }
  }
  $('connect-form').addEventListener('submit', event => {
    event.preventDefault();
    try {
      const url = new URL($('endpoint').value);
      if (!safeEndpoint(url)) throw new Error('endpoint');
      const secret = $('token').value.trim(); if (!/^[a-f0-9]{64}$/.test(secret)) throw new Error('token');
      generation++; busy = false; endpoint = url.origin; token = secret; paired = true; last = null; failed = false; $('token').value = '';
      try { sessionStorage.setItem('quotadock.endpoint', endpoint); sessionStorage.setItem('quotadock.token', token); } catch { $('connection-message').textContent = '세션 저장이 차단되어 이 페이지에서만 연결을 유지합니다.'; }
      refresh();
    } catch { $('connection-message').textContent = '이 페이지와 같은 브리지 주소와 64자리 페어링 토큰을 입력해 주세요. HTTP는 로컬 루프백에서만 가능합니다.'; }
  });
  $('disconnect').addEventListener('click', () => {
    generation++; busy = false; paired = false; token = ''; last = null; failed = false;
    try { sessionStorage.removeItem('quotadock.endpoint'); sessionStorage.removeItem('quotadock.token'); } catch {}
    $('token').value = ''; $('status').textContent = '브리지를 연결해 주세요'; $('connection-message').textContent = ''; render();
  });
  $('refresh').addEventListener('click', () => { if (demo) { $('status').textContent = 'DEMO · 로컬 예시 데이터입니다'; render(); } else refresh(); });
  if (demo) {
    const now = Date.now(); const reset = hours => new Date(now + hours * 3600000).toISOString();
    last = { schemaVersion: 1, generatedAt: new Date(now).toISOString(), demo: true, providers: [
      { id:'claude', plan:'Max', state:'available', source:'demo', observedAt:new Date(now).toISOString(), windows:[{label:'Session',remainingPercent:72,resetsAt:reset(3)},{label:'Weekly',remainingPercent:91,resetsAt:reset(96)}] },
      { id:'codex', plan:'ChatGPT Pro', state:'available', source:'demo', observedAt:new Date(now).toISOString(), windows:[{label:'5-hour',remainingPercent:84,resetsAt:reset(2)},{label:'Weekly',remainingPercent:63,resetsAt:reset(72)}] },
      { id:'gemini', plan:'Standard', state:'available', source:'demo', observedAt:new Date(now).toISOString(), windows:[{label:'Pro model tier',remainingPercent:88,resetsAt:reset(12)},{label:'Flash model tier',remainingPercent:96,resetsAt:reset(12)}] },
      { id:'grok', plan:null, state:'unavailable', source:'demo', observedAt:null, windows:[{label:'사용량',remainingPercent:null,resetsAt:null}] }
    ] };
    document.querySelector('.connection').hidden = true;
  } else {
    try { endpoint = sessionStorage.getItem('quotadock.endpoint') || ''; token = sessionStorage.getItem('quotadock.token') || ''; const url = new URL(endpoint); paired = /^[a-f0-9]{64}$/.test(token) && safeEndpoint(url); } catch { paired = false; }
    $('endpoint').value = paired ? endpoint : location.origin;
  }
  if (demo) $('status').textContent = 'DEMO · 로컬 예시 데이터입니다';
  render(); if (paired) refresh();
  setInterval(() => { if (paired) refresh(); else if (demo) render(); }, 60000);
})();
