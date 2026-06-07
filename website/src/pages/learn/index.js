import React from 'react';
import Layout from '@theme/Layout';
import LearnHome from '../../components/LearnHome';

export default function Learn() {
  return (
    <Layout
      title="Learn N# — Systems learning path"
      description="Two paths into N#'s systems lane: a fast tour for experienced perf engineers, or a from-scratch, puzzle-based course on high-performance code.">
      <LearnHome />
    </Layout>
  );
}
