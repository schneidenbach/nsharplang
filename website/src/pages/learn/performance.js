import React from 'react';
import Layout from '@theme/Layout';
import PerformanceCourse from '../../components/PerformanceCourse';

export default function Performance() {
  return (
    <Layout
      title="High Performance from Scratch — Learn N#"
      description="A puzzle-based course that teaches high-performance code from scratch using N#, with C# and Rust contrasts and real measured speed and memory telemetry.">
      <PerformanceCourse />
    </Layout>
  );
}
