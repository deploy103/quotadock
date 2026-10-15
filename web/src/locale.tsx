import { useEffect, useState } from 'react';

export type Language = 'en' | 'ko';
type Preference = Language | 'system';
const key = 'quotadock.language';
const systemLanguage = (): Language => navigator.language.toLowerCase().split('-')[0] === 'ko' ? 'ko' : 'en';
const valid = (value: string | null): Preference => value === 'en' || value === 'ko' ? value : 'system';
const korean: Readonly<Record<string, string>> = { 'YOUR AI, AT A GLANCE': '내 AI 사용량을 한눈에', 'DEMO · SAMPLE DATA': 'DEMO · 예시 데이터', 'BRIDGE · ERROR': '브리지 · 오류', 'BRIDGE PAIRED': '브리지 연결됨', 'NOT CONNECTED': '연결되지 않음', 'STALE': '오래됨 · STALE', 'LIVE': '최근 관측' };
export function useLanguage() {
  const [preference, setPreference] = useState<Preference>(() => { try { return valid(localStorage.getItem(key)); } catch { return 'system'; } });
  const [system, setSystem] = useState(systemLanguage);
  const language = preference === 'system' ? system : preference;
  useEffect(() => {
    const changed = () => setSystem(systemLanguage());
    const stored = (event: StorageEvent) => { if (event.key === key || event.key === null) setPreference(valid(event.newValue)); };
    window.addEventListener('languagechange', changed); window.addEventListener('storage', stored);
    return () => { window.removeEventListener('languagechange', changed); window.removeEventListener('storage', stored); };
  }, []);
  useEffect(() => { document.documentElement.lang = language; document.title = language === 'ko' ? 'QuotaDock · 사용량 보드' : 'QuotaDock · Quota board'; }, [language]);
  const control = <label className="setting">{language === 'ko' ? '언어' : 'Language'} <select aria-label={language === 'ko' ? '언어' : 'Language'} value={preference} onChange={event => {
    const next = valid(event.target.value); setPreference(next);
    try { localStorage.setItem(key, next); } catch { /* In-memory preference still works. */ }
  }}><option value="system">{language === 'ko' ? '시스템 기본값' : 'System default'}</option><option value="en">English</option><option value="ko">한국어</option></select></label>;
  return { language, control };
}

// Only explicitly selected UI labels are translated; upstream data stays raw.
export function translate(value: string, language: Language, dictionary: Readonly<Record<string, string>>): string {
  return language === 'ko' ? korean[value] ?? (value === 'DEMO · STALE' ? 'DEMO · 오래됨 · STALE' : value) : dictionary[value] ?? value;
}
