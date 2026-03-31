// @ts-check

/** @type {import('@docusaurus/plugin-content-docs').SidebarsConfig} */
const sidebars = {
  docsSidebar: [
    {
      type: 'category',
      label: 'Getting Started',
      collapsed: false,
      items: [
        'quick-start',
        'getting-started',
        'basics',
        'language-tour',
      ],
    },
    {
      type: 'category',
      label: 'Language Guide',
      collapsed: false,
      items: [
        'functions',
        'types',
        'pattern-matching',
      ],
    },
    {
      type: 'category',
      label: 'Tooling',
      collapsed: false,
      items: [
        'cli-reference',
        'debugging',
        'ci-cd',
      ],
    },
    {
      type: 'category',
      label: 'Migration & Interop',
      collapsed: true,
      items: [
        'for-csharp-developers',
        'for-go-developers',
        'csharp-migration',
        'interop',
      ],
    },
  ],
};

export default sidebars;
