import React from 'react';
import {Database, Gauge, Info} from 'lucide-react';
import {telemetryMeta, languageOrder} from '../data/perfTelemetry.mjs';

function formatNs(value) {
  if (value >= 1000) {
    return `${(value / 1000).toFixed(2)} µs`;
  }
  if (value >= 100) {
    return `${value.toFixed(0)} ns`;
  }
  return `${value.toFixed(2)} ns`;
}

function formatBytes(value) {
  if (value === 0) {
    return '0 B';
  }
  if (value >= 1024) {
    return `${(value / 1024).toFixed(value >= 10240 ? 0 : 1)} KB`;
  }
  return `${value} B`;
}

// A row of bars over the four languages. `lower-is-better` so the longest bar is
// the slowest — visually "shorter = faster".
function SpeedBars({speed}) {
  const max = Math.max(speed.nsharp, speed.csharp, speed.rust, speed.c);
  const best = Math.min(speed.nsharp, speed.csharp, speed.rust, speed.c);
  return (
    <div className="telemetry-bars">
      {languageOrder.map(({key, label}) => {
        const value = speed[key];
        const pct = Math.max((value / max) * 100, 2);
        const relToCsharp = speed.csharp / value;
        return (
          <div className="telemetry-bars__row" key={key}>
            <span className="telemetry-bars__lang">{label}</span>
            <span className="telemetry-bars__track">
              <span
                className={`telemetry-bars__fill telemetry-bars__fill--${key}`}
                style={{width: `${pct}%`}}
              />
            </span>
            <span className="telemetry-bars__val">
              <b>{formatNs(value)}</b>
              {key === 'nsharp' && value !== best && relToCsharp >= 1.05
                ? ` · ${relToCsharp.toFixed(1)}× vs C#`
                : ''}
            </span>
          </div>
        );
      })}
    </div>
  );
}

function MemoryBars({rows, unit}) {
  const max = Math.max(...rows.map((row) => row.bytes), 1);
  return (
    <div className="telemetry-bars">
      {rows.map((row, index) => {
        const pct = row.bytes === 0 ? 2 : Math.max((row.bytes / max) * 100, 4);
        const isZero = row.bytes === 0;
        return (
          <div className="telemetry-bars__row" key={index} style={{gridTemplateColumns: '1fr'}}>
            <div style={{display: 'flex', justifyContent: 'space-between', gap: 10, alignItems: 'baseline'}}>
              <span className="telemetry-bars__lang" style={{fontWeight: 500}}>{row.label}</span>
              <span className="telemetry-bars__val"><b>{formatBytes(row.bytes)}</b>{unit && unit !== 'B' ? `/${unit}` : ''}</span>
            </div>
            <span className="telemetry-bars__track" style={{gridColumn: '1 / -1'}}>
              <span
                className={`telemetry-bars__fill telemetry-bars__fill--${isZero ? 'nsharp' : 'csharp'}`}
                style={{width: `${pct}%`, opacity: isZero ? 0.5 : 1}}
              />
            </span>
            {row.note && <span className="telemetry-bars__val" style={{textAlign: 'left', gridColumn: '1 / -1'}}>{row.note}</span>}
          </div>
        );
      })}
    </div>
  );
}

function Provenance() {
  return (
    <details className="telemetry-provenance">
      <summary>How these numbers were measured</summary>
      <ul>
        <li>Hardware: {telemetryMeta.machine} · {telemetryMeta.runtime} · {telemetryMeta.native}</li>
        <li>Method: {telemetryMeta.method}</li>
        <li>Measured: {telemetryMeta.measured}. Reproduce: <code>{telemetryMeta.reproduce}</code></li>
        {telemetryMeta.caveats.map((caveat, index) => (
          <li key={index}>{caveat}</li>
        ))}
      </ul>
    </details>
  );
}

export default function TelemetryPanel({kernel, allocationStory}) {
  const headlineClass = kernel
    ? (kernel.vectorized ? 'telemetry-headline telemetry-headline--win' : 'telemetry-headline telemetry-headline--honest')
    : 'telemetry-headline';

  return (
    <div>
      <div className="telemetry">
        {/* Speed */}
        <div className="telemetry-block">
          <h4 className="telemetry-block__title">
            <Gauge size={15} aria-hidden="true" /> Speed
            <span className="telemetry-tag telemetry-tag--measured">measured</span>
          </h4>
          {kernel ? (
            <>
              <p className="telemetry-block__sub">{kernel.blurb} — time per call, lower is faster.</p>
              <SpeedBars speed={kernel.speed} />
              <div className={headlineClass}>{kernel.headline}</div>
            </>
          ) : (
            <p className="telemetry-block__sub">
              This concept is about <em>hidden cost</em>, not a single timed kernel — the speed payoff is
              avoiding the heap allocations and indirect calls shown on the right entirely.
            </p>
          )}
        </div>

        {/* Memory */}
        <div className="telemetry-block">
          <h4 className="telemetry-block__title">
            <Database size={15} aria-hidden="true" /> Memory
            {allocationStory ? (
              <span className="telemetry-tag telemetry-tag--illustrative">illustrative</span>
            ) : (
              <span className="telemetry-tag telemetry-tag--measured">measured</span>
            )}
          </h4>
          {allocationStory ? (
            <>
              <p className="telemetry-block__sub">{allocationStory.title} — bytes allocated on the heap.</p>
              <MemoryBars rows={allocationStory.rows} unit={allocationStory.unit} />
              <div className="telemetry-headline telemetry-headline--win">{allocationStory.takeaway}</div>
            </>
          ) : kernel ? (
            <>
              <p className="telemetry-block__sub">Heap bytes allocated per call.</p>
              <MemoryBars
                rows={languageOrder.map(({key, label}) => ({label, bytes: kernel.memory[key], note: null}))}
                unit={kernel.memory.unit}
              />
              <div className="telemetry-headline">{kernel.memory.note}</div>
            </>
          ) : null}
        </div>
      </div>

      {kernel && kernel.detail && (
        <p className="telemetry-block__sub" style={{marginTop: 14, display: 'flex', gap: 7}}>
          <Info size={14} aria-hidden="true" style={{flexShrink: 0, marginTop: 2}} />
          <span>{kernel.detail}</span>
        </p>
      )}

      <Provenance />
    </div>
  );
}
