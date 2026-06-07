import React from 'react';
import useBaseUrl from '@docusaurus/useBaseUrl';
import Link from '@docusaurus/Link';
import CodeBlock from '@theme/CodeBlock';
import {ArrowRight, Gauge, GraduationCap} from 'lucide-react';
import {Markdown, renderInline} from '../lib/miniMarkdown';
import {kernels, telemetryMeta, languageOrder} from '../data/perfTelemetry.mjs';
import tour from '../data/systemsTour.json';

function fmt(value) {
  if (value >= 1000) {
    return `${(value / 1000).toFixed(2)} µs`;
  }
  if (value >= 100) {
    return `${value.toFixed(0)} ns`;
  }
  return `${value.toFixed(2)} ns`;
}

// Compact measured cross-language table (size 4096) for the perf-engineer audience.
function MeasuredTable() {
  const rows = Object.values(kernels);
  return (
    <div className="perf-table-wrap">
      <table className="perf-table">
        <thead>
          <tr>
            <th>Kernel (4096 i32)</th>
            {languageOrder.map((lang) => <th key={lang.key}>{lang.label}</th>)}
            <th>N# vs C#</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((kernel) => {
            const best = Math.min(kernel.speed.nsharp, kernel.speed.csharp, kernel.speed.rust, kernel.speed.c);
            const ratio = kernel.speed.csharp / kernel.speed.nsharp;
            return (
              <tr key={kernel.label}>
                <td>{kernel.label}</td>
                {languageOrder.map((lang) => (
                  <td key={lang.key} className={kernel.speed[lang.key] === best ? 'is-best' : ''}>
                    {fmt(kernel.speed[lang.key])}
                  </td>
                ))}
                <td className={ratio >= 1.1 ? 'perf-table__win' : ''}>
                  {ratio >= 1.05 ? `${ratio.toFixed(2)}× faster` : ratio <= 0.95 ? `${(1 / ratio).toFixed(2)}× slower` : 'tied'}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

export default function SystemsTour() {
  return (
    <div className="learn-page">
      <div className="learn-breadcrumb">
        <Link to={useBaseUrl('/learn')}>Learn</Link>
        <span>›</span>
        <span>Systems N# Tour</span>
      </div>

      <div className="learn-hero">
        <span className="learn-hero__eyebrow"><Gauge size={12} aria-hidden="true" /> For people who already write fast code</span>
        <h1 className="learn-hero__title">{tour.hero.title}</h1>
        <p className="learn-hero__lede">{renderInline(tour.hero.lede)}</p>
      </div>

      <div className="tour-pillars">
        {tour.pillars.map((pillar) => (
          <article className="tour-pillar" key={pillar.title}>
            <div className="tour-pillar__body">
              <p className="tour-pillar__opinion">{pillar.opinion}</p>
              <h2 className="tour-pillar__title">{pillar.title}</h2>
              <div className="tour-pillar__text"><Markdown text={pillar.body} /></div>
            </div>
            <div className="tour-pillar__code">
              <CodeBlock language="nsharp">{pillar.code}</CodeBlock>
            </div>
          </article>
        ))}
      </div>

      <section>
        <div className="section__header" style={{padding: 0, marginBottom: 10}}>
          <h2 className="section__title">Measured, cross-language</h2>
          <p className="section__subtitle">
            {telemetryMeta.machine} · {telemetryMeta.runtime} · {telemetryMeta.native} · {telemetryMeta.measured}.
            Time per call at 4096 i32, lower is faster.
          </p>
        </div>
        <MeasuredTable />
        <details className="telemetry-provenance">
          <summary>Method &amp; caveats</summary>
          <ul>
            <li>{telemetryMeta.method}</li>
            <li>Reproduce: <code>{telemetryMeta.reproduce}</code></li>
            {telemetryMeta.caveats.map((caveat, index) => <li key={index}>{caveat}</li>)}
          </ul>
        </details>
      </section>

      <div className="tour-closing">
        <h2>Where N# stands today</h2>
        <p>{renderInline(tour.closing)}</p>
      </div>

      <div className="hero__buttons">
        <Link className="btn--primary" to={useBaseUrl('/docs/getting-started')}>Get started</Link>
        <Link className="btn--secondary" to={useBaseUrl('/learn/performance')}>
          <GraduationCap size={14} aria-hidden="true" style={{marginRight: 6}} /> Start from scratch instead
        </Link>
        <Link className="btn--secondary" to={useBaseUrl('/playground')}>Open the playground <ArrowRight size={13} aria-hidden="true" /></Link>
      </div>
    </div>
  );
}
