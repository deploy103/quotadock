import { useEffect, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { demoSnapshot, fetchSnapshot, names, safeEndpoint } from './client';
import type { Pairing, ProviderId, Snapshot } from './client';
import { translate, useLanguage } from './locale';
import { english, koreanWindows } from './translations';
import '../style.css';

const demo = new URLSearchParams(location.search).get('demo') === '1';
const providerIds: readonly ProviderId[] = ['claude', 'codex', 'gemini', 'grok'];
const stale = (v: string | null) => !v || Date.now() - Date.parse(v) > 900000;
function restored(): Pairing | null {
  if (demo) return null;
  try {
    const endpoint = sessionStorage.getItem('quotadock.endpoint') || '', token = sessionStorage.getItem('quotadock.token') || '';
    return safeEndpoint(new URL(endpoint)) && /^[a-f0-9]{64}$/.test(token) ? { endpoint, token } : null;
  } catch { return null; }
}
function App() {
  const { language, control } = useLanguage();
  const t = (value: string) => translate(value, language, english);
  const date = (v: string | null) => !v || !Number.isFinite(Date.parse(v)) ? t('알 수 없음') : new Intl.DateTimeFormat(language === 'ko' ? 'ko-KR' : 'en-US', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit', timeZoneName: 'short' }).format(new Date(v));
  const number = new Intl.NumberFormat(language === 'ko' ? 'ko-KR' : 'en-US', { maximumFractionDigits: 2 });
  const windowLabel = (value: string) => language === 'ko' ? koreanWindows[value] || value : value === '사용량' ? t('사용량') : value;
  const [guide, setGuide] = useState(() => { try { return localStorage.getItem('quotadock.guide-dismissed') !== '1'; } catch { return true; } });
  const [pair, setPair] = useState(restored);
  const pairing = useRef(pair);
  const [endpoint, setEndpoint] = useState(pair?.endpoint || location.origin);
  const [token, setToken] = useState('');
  const [last, setLast] = useState<Snapshot | null>(() => demo ? demoSnapshot() : null);
  const lastRef = useRef(last);
  const [failed, setFailed] = useState(false), [busy, setBusy] = useState(false);
  const [auto, setAuto] = useState(!demo);
  const [status, setStatus] = useState(demo ? 'DEMO · 로컬 예시 데이터입니다' : '브리지를 연결해 주세요');
  const [message, setMessage] = useState('');
  const generation = useRef(0), active = useRef<AbortController | null>(null), inFlight = useRef(false);
  const endpointInput = useRef<HTMLInputElement>(null);
  function cancel() { generation.current++; active.current?.abort(); active.current = null; inFlight.current = false; setBusy(false); }
  async function refresh() {
    const current = pairing.current;
    if (!current || inFlight.current || document.hidden) return;
    const version = generation.current;
    inFlight.current = true; setBusy(true); setStatus('사용량 확인 중…');
    const controller = new AbortController(); active.current = controller;
    const timeout = setTimeout(() => controller.abort(), 15000);
    try {
      const snapshot = await fetchSnapshot(current, controller.signal);
      if (version !== generation.current) return;
      lastRef.current = snapshot; setLast(snapshot); setFailed(false); setMessage('');
      setStatus(snapshot.providers.some(p => p.state === 'available' && stale(p.observedAt)) ? '오래된 관측 데이터가 있습니다' : '남은 사용량을 확인했어요');
    } catch {
      if (version !== generation.current) return;
      setFailed(true); setStatus(lastRef.current ? '연결 오류 · 마지막 데이터 표시 중' : '브리지에 연결하지 못했습니다');
      setMessage('주소, 토큰, HTTPS 인증서와 브리지의 접근 허용 설정을 확인해 주세요. 자동 확인을 끈 경우 수동으로 다시 확인하세요.');
    } finally {
      clearTimeout(timeout);
      if (version === generation.current) { inFlight.current = false; active.current = null; setBusy(false); }
    }
  }
  useEffect(() => { void refresh(); return () => { generation.current++; active.current?.abort(); }; }, []);
  useEffect(() => {
    let timer: ReturnType<typeof setInterval> | undefined;
    function schedule() { clearInterval(timer); timer = undefined; if (!document.hidden && auto && pair) timer = setInterval(() => { void refresh(); }, 60000); }
    function visibility() { if (document.hidden) cancel(); schedule(); if (!document.hidden && auto && pair) void refresh(); }
    schedule(); document.addEventListener('visibilitychange', visibility);
    return () => { clearInterval(timer); document.removeEventListener('visibilitychange', visibility); };
  }, [auto, pair]);
  function disconnect() {
    cancel(); pairing.current = null; setPair(null); lastRef.current = null; setLast(null); setFailed(false); setToken(''); setStatus('브리지를 연결해 주세요'); setMessage('');
    try { sessionStorage.removeItem('quotadock.endpoint'); sessionStorage.removeItem('quotadock.token'); } catch { /* Storage may be disabled. */ }
    endpointInput.current?.focus();
  }
  return <div className="shell">
    <header className="masthead"><a className="brand" href="/">◈ QuotaDock</a>{control}<span id="mode" className="badge">{t(demo || last?.demo ? 'DEMO · SAMPLE DATA' : pair ? failed ? 'BRIDGE · ERROR' : 'BRIDGE PAIRED' : 'NOT CONNECTED')}</span></header>
    {guide && !demo && <section className="connection" aria-labelledby="guide-title"><h2 id="guide-title">{t('처음 연결하시나요?')}</h2><p>{t('로컬 브리지에서 발급한 토큰을 사용하세요. AI 계정 비밀번호를 입력하지 마세요. 연결하기를 눌러 페어링하세요. 이미 연결한 탭은 저장된 세션으로 자동 확인을 재개할 수 있습니다.')}</p><a href="/?demo=1">{t('로그인 없이 데모 살펴보기')}</a><p>{t('표시값은 마지막 관측입니다. 로컬 수집기가 오프라인이면 새 값이 없습니다. OS 위젯은 저장값만 표시하며 갱신 시점은 OS가 결정합니다.')}</p><button type="button" onClick={() => { setGuide(false); try { localStorage.setItem('quotadock.guide-dismissed', '1'); } catch { /* Dismiss for this page. */ } endpointInput.current?.focus(); }}>{t('연결 안내 닫기')}</button></section>}
    <main><section className="intro"><div><p className="eyebrow">{t('YOUR AI, AT A GLANCE')}</p><h1>{t('남은 여유, 한눈에.')}</h1><p className="muted">{t('계정별로, 사용량 창별로. 다음 작업 전에 확인하세요.')}</p></div>
      <div className="status-box"><strong id="status" role="status" aria-live="polite">{t(status)}</strong><p id="updated">{last ? `${t('스냅샷')} · ${date(last.generatedAt)} · ${t(demo ? '로컬 예시' : auto ? '화면이 보일 때 60초마다 확인' : '수동 확인')}` : t('아직 받은 데이터가 없습니다.')}</p><button id="refresh" disabled={busy || (!pair && !demo)} onClick={() => demo ? setStatus('DEMO · 로컬 예시 데이터입니다') : void refresh()}>↻ {t('지금 새로고침')}</button></div></section>
      <section className="connection" hidden={demo} aria-labelledby="setup-title"><h2 id="setup-title">{t('브리지 연결')}</h2><p>{t('이 페이지와 같은 브리지 주소와 페어링 토큰을 입력하세요. AI 서비스 비밀번호가 아닙니다. HTTP는 로컬 루프백만 허용하며 토큰은 이 탭의 세션에만 저장됩니다.')}</p>
        <form id="connect-form" onSubmit={event => {
          event.preventDefault();
          try {
            const url = new URL(endpoint), secret = token.trim();
            if (!safeEndpoint(url) || !/^[a-f0-9]{64}$/.test(secret)) throw new Error('pairing');
            cancel(); const next = { endpoint: url.origin, token: secret }; pairing.current = next; setPair(next); setToken(''); lastRef.current = null; setLast(null); setFailed(false); setMessage('');
            try { sessionStorage.setItem('quotadock.endpoint', next.endpoint); sessionStorage.setItem('quotadock.token', next.token); } catch { setMessage('세션 저장이 차단되어 이 페이지에서만 연결을 유지합니다.'); }
            void refresh();
          } catch { setMessage('이 페이지와 같은 브리지 주소와 64자리 페어링 토큰을 입력해 주세요. HTTP는 로컬 루프백에서만 가능합니다.'); }
        }}><label>{t('브리지 주소')}<input ref={endpointInput} id="endpoint" type="url" required autoComplete="url" placeholder="https://bridge.example.com" value={endpoint} onChange={e => setEndpoint(e.target.value)} /></label><label>{t('페어링 토큰')}<input id="token" type="password" required autoComplete="off" spellCheck={false} placeholder={t('64자리 토큰')} value={token} onChange={e => setToken(e.target.value)} /></label><button type="submit">{t('연결하기')} ↗</button><button id="disconnect" className="secondary" type="button" hidden={!pair} onClick={disconnect}>{t('연결 해제')}</button></form><p id="connection-message" role="alert">{t(message)}</p></section>
      <div className="section-head"><h2>{t('사용량 보드')}</h2><label className="setting"><input id="auto-refresh" type="checkbox" checked={auto} disabled={demo} onChange={e => setAuto(e.target.checked)} /> {t('자동 확인 · 60초')}</label></div><p className="muted small">{t('자동 확인은 화면이 보일 때만 동작합니다. 끄면 수동으로만 확인합니다.')}</p>
      <section id="providers" className="providers" aria-label={t('제공자별 남은 사용량')}>{providerIds.map(id => {
        const name = names[id], p = last?.providers.find(p => p.id === id), old = p?.state === 'available' && (failed || stale(p.observedAt)), sample = demo || last?.demo || p?.source === 'demo';
        return <article key={id} className={`provider${old ? ' is-stale' : ''}`}><div className="provider-header"><div className="provider-title"><img className="provider-icon" src={`/icons/${id}.svg`} alt="" width="38" height="38" /><div><h3>{name}</h3><div className="plan">{t('플랜')} · {p?.plan || t('알 수 없음')}</div></div></div><span className={`badge${old ? ' is-stale' : ''}`}>{t(sample ? old ? 'DEMO · STALE' : 'DEMO' : !p ? '미연결' : p.state !== 'available' ? '확인 불가' : old ? 'STALE' : 'LIVE')}</span></div>
          {id === 'codex' && <p className="provider-note">{t('Codex 허용량 · 전체 ChatGPT 사용량 아님. Free 지원은 화면·롤아웃에 따라 다르며 측정 불가는 알 수 없음입니다.')}</p>}{id === 'gemini' && <p className="provider-note">{t('모델 티어별 할당량 · 각 창을 따로 확인하세요')}</p>}
          {(!p || !p.windows.length) && <p className="unknown">{t(!p ? '연결 후 남은 사용량을 확인할 수 있어요.' : '사용량을 확인할 수 없습니다. 추정하지 않습니다.')}</p>}
          {p?.windows.map((w, i) => {
            const amount = p.state === 'available' && w.remainingPercent !== null ? Math.min(100, Math.max(0, w.remainingPercent)) : null;
            return <div key={i} className="window"><div className="window-heading"><span>{windowLabel(w.label)}</span><strong>{amount === null ? t('알 수 없음') : `${number.format(amount)}% ${t('남음')}`}</strong></div>{amount === null ? <p className="unknown">{t('측정된 사용량 없음 · 추정 막대 없음')}</p> : <progress className="track" max={100} value={amount} aria-label={`${name} ${windowLabel(w.label)} ${t('남은 사용량')}`} aria-valuemin={0} aria-valuemax={100} aria-valuenow={amount} />}<p className="reset">{t('리셋')} · {date(w.resetsAt)}</p></div>;
          })}{p?.state === 'error' && <p className="stale">{t('제공자 데이터를 가져오지 못했습니다.')}</p>}<div className="source">{t('출처')} · {p ? p.source === 'demo' ? t('DEMO 예시') : 'CodexBar' : t('미연결')} / {t('관측')} · {p ? date(p.observedAt) : t('없음')}{old ? ` · ${t('오래된 데이터')}` : ''}</div></article>;
      })}</section><footer><strong>{t('측정값만, 추정 없이.')}</strong><p>{t('알 수 없음은 0%가 아닙니다. 리셋 시각은 참고 정보이며 새 할당량을 보장하지 않습니다. 브리지 캐시는 60초입니다.')}</p><a href="https://github.com/deploy103/quotadock">{t('소스 · 설치 안내')} ↗</a></footer>
    </main></div>;
}
const root = document.getElementById('root');
if (!root) throw new Error('Missing dashboard root');
createRoot(root).render(<App />);
