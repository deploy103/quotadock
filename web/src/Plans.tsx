import { useEffect } from 'react';
import { translate, useLanguage } from './locale';
import { english } from './translations';

// The bridge has no billing session; this comparison never starts checkout.
export function PlansPage() {
  const { language, control } = useLanguage();
  const t = (value: string) => translate(value, language, english);
  useEffect(() => { document.title = `QuotaDock · ${t('요금제')}`; }, [language]);
  const plans = [
    { name: 'Free', price: t('무료'), period: '', features: ['계정 3개 · 2시간 간격', '조기 갱신 10회 / 한국 시간 하루'] },
    { name: 'Plus', price: new Intl.NumberFormat(language === 'ko' ? 'ko-KR' : 'en-US', { style: 'currency', currency: 'KRW', maximumFractionDigits: 0 }).format(3990), period: t('/ 월'), features: ['계정 10개 · 1시간 간격', 'Live 5회 / 구독 기간'] },
    { name: 'Pro', price: t('가격 미정'), period: '', features: ['계정 무제한 · 20–120분 간격', 'Live 5회 / 한국 시간 하루'] },
  ];
  return <div className="shell plans-shell">
    <header className="masthead"><a className="brand" href="/">QuotaDock</a>{control}</header>
    <main className="plans-page">
      <div className="plans-heading"><h1>{t('요금제')}</h1></div>
      <div className="plan-cards">{plans.map(plan => <article className="plan-card" key={plan.name} aria-labelledby={`plan-${plan.name}`}>
        <h2 id={`plan-${plan.name}`}>{plan.name}</h2>
        <p className="plan-price">{plan.price} <span>{plan.period}</span></p>
        <ul>{plan.features.map(feature => <li key={feature}>{t(feature)}</li>)}</ul>
      </article>)}</div>
      <p className="plans-note">{t('새 관측에는 온라인 로컬 수집기가 필요해요. AI 서비스 요금은 별도예요.')}</p>
      <details className="plan-terms"><summary>{t('결제 안내·약관')}</summary>
        <p>{t('최종 결제 가격은 Apple에서 확인해요. 갱신은 한 번에 최대 50계정, 횟수는 성공한 배치 기준이에요. Live는 최대 30분이며 수집 시각은 보장하지 않아요.')}</p>
        <p>{t('구독은 매월 자동 갱신돼요. Apple 구독 설정에서 해지할 수 있어요. 앱 계정 삭제로 구독이 해지되지는 않아요.')}</p>
        <div className="plan-links"><a href="https://usage.mvtp.cloud/#privacy">{t('개인정보')}</a><a href="https://www.apple.com/legal/internet-services/itunes/dev/stdeula/">{t('이용약관')}</a></div>
      </details>
      <a className="plans-back" href="/">← {t('사용량 보드')}</a>
    </main>
  </div>;
}
