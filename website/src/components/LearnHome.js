import React from 'react';
import Link from '@docusaurus/Link';
import {ArrowRight, Check, Gauge, GraduationCap, Zap} from 'lucide-react';

const paths = [
  {
    to: '/learn/systems',
    icon: <Gauge size={20} aria-hidden="true" />,
    kicker: 'I already know high-performance code',
    title: 'The Systems N# Tour',
    desc:
      'A fast, opinionated walk through the features and stances of N#’s systems lane — the effect model, ' +
      'Result, spans and lifetimes, governed unsafe, and auto-vectorization — with the measured numbers up front.',
    bullets: [
      'Respects your time: pillars, not a tutorial',
      'The [hot]/[boundary] effect model and the NSYS cost family',
      'Honest, measured positioning vs C#, Rust, and C',
    ],
    cta: 'Take the tour',
  },
  {
    to: '/learn/performance',
    icon: <GraduationCap size={20} aria-hidden="true" />,
    kicker: 'Teach me high-performance code from scratch',
    title: 'High Performance from Scratch',
    desc:
      'A puzzle-based course that builds your performance intuition one idea at a time — memory, allocation, ' +
      'branches, SIMD, dispatch — using N# as the teaching language, with C# and Rust side by side and real telemetry.',
    bullets: [
      'Eight modules, each a concept + a code puzzle you solve to advance',
      'Live in-browser N# runner; measured speed and memory on every kernel',
      'No prior systems background assumed',
    ],
    cta: 'Start learning',
  },
];

export default function LearnHome() {
  return (
    <div className="learn-page">
      <div className="learn-hero">
        <span className="learn-hero__eyebrow"><Zap size={12} aria-hidden="true" /> Systems learning path</span>
        <h1 className="learn-hero__title">Learn to write fast code on the CLR</h1>
        <p className="learn-hero__lede">
          N# has a systems lane that makes performance costs visible, checkable, and explainable. Pick the
          path that fits where you’re starting from — a quick tour if you already think in cache lines and SIMD,
          or a from-scratch course if you want to build that intuition.
        </p>
      </div>

      <div className="learn-paths">
        {paths.map((path) => (
          <Link className="learn-path-card" to={path.to} key={path.to}>
            <span className="learn-path-card__icon">{path.icon}</span>
            <span className="learn-path-card__kicker">{path.kicker}</span>
            <span className="learn-path-card__title">{path.title}</span>
            <p className="learn-path-card__desc">{path.desc}</p>
            <ul className="learn-path-card__list">
              {path.bullets.map((bullet) => (
                <li key={bullet}><Check size={14} aria-hidden="true" /><span>{bullet}</span></li>
              ))}
            </ul>
            <span className="learn-path-card__cta">{path.cta} <ArrowRight size={15} aria-hidden="true" /></span>
          </Link>
        ))}
      </div>
    </div>
  );
}
