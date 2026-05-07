// @ts-check
import {themes as prismThemes} from 'prism-react-renderer';

/** @type {import('@docusaurus/types').Config} */
const config = {
  title: 'N#',
  tagline: 'Simple by design. Powerful by .NET.',
  favicon: 'favicon.svg',

  future: {
    v4: true,
  },

  url: 'https://schneidenbach.github.io',
  baseUrl: '/nsharplang/',

  organizationName: 'schneidenbach',
  projectName: 'nsharplang',

  onBrokenLinks: 'warn',

  markdown: {
    format: 'md',
  },

  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },

  presets: [
    [
      'classic',
      /** @type {import('@docusaurus/preset-classic').Options} */
      ({
        docs: {
          sidebarPath: './sidebars.js',
          editUrl: 'https://github.com/schneidenbach/nsharplang/tree/main/website/',
        },
        blog: false,
        theme: {
          customCss: './src/css/custom.css',
        },
      }),
    ],
  ],

  themeConfig:
    /** @type {import('@docusaurus/preset-classic').ThemeConfig} */
    ({
      image: 'favicon.svg',
      colorMode: {
        defaultMode: 'light',
        disableSwitch: true,
        respectPrefersColorScheme: false,
      },
      navbar: {
        title: 'N#',
        logo: {
          alt: 'N# Logo',
          src: 'favicon.svg',
        },
        items: [
          {
            type: 'docSidebar',
            sidebarId: 'docsSidebar',
            position: 'left',
            label: 'Docs',
          },
          {to: '/examples', label: 'Examples', position: 'left'},
          {
            href: 'https://github.com/schneidenbach/nsharplang',
            label: 'GitHub',
            position: 'right',
          },
        ],
      },
      footer: {
        style: 'light',
        links: [
          {
            title: 'Learn',
            items: [
              {label: 'Getting Started', to: '/docs/getting-started'},
              {label: 'Language Tour', to: '/docs/language-tour'},
              {label: 'CLI Reference', to: '/docs/cli-reference'},
            ],
          },
          {
            title: 'Migrate',
            items: [
              {label: 'Coming from C#', to: '/docs/for-csharp-developers'},
              {label: 'Coming from Go', to: '/docs/for-go-developers'},
              {label: 'C# Interop', to: '/docs/interop'},
            ],
          },
          {
            title: 'More',
            items: [
              {label: 'Examples', to: '/examples'},
              {
                label: 'GitHub',
                href: 'https://github.com/schneidenbach/nsharplang',
              },
              {
                label: 'Issues',
                href: 'https://github.com/schneidenbach/nsharplang/issues',
              },
            ],
          },
        ],
        copyright: `Copyright © ${new Date().getFullYear()} N# Language. Open source.`,
      },
      prism: {
        theme: prismThemes.github,
        darkTheme: prismThemes.dracula,
        additionalLanguages: ['csharp', 'bash', 'yaml', 'json', 'xml-doc'],
      },
    }),
};

export default config;
