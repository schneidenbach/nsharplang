import React from 'react';
import Layout from '@theme/Layout';
import SystemsTour from '../../components/SystemsTour';

export default function Systems() {
  return (
    <Layout
      title="The Systems N# Tour — Learn N#"
      description="A fast, opinionated tour of N#'s systems lane: the effect model, Result, spans and lifetimes, governed unsafe, and auto-vectorization, with measured cross-language numbers.">
      <SystemsTour />
    </Layout>
  );
}
