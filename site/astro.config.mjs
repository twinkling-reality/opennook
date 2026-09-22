// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

// https://astro.build/config
export default defineConfig({
  site: 'https://opennook.dev',
  integrations: [
    starlight({
      title: 'OpenNook',
      description: 'An open-source framework for building macOS notch apps.',
      logo: {
        alt: 'OpenNook',
        src: './src/assets/nook-mark.svg',
        replacesTitle: false,
      },
      social: [
        { icon: 'github', label: 'GitHub', href: 'https://github.com/twinkling-reality/opennook' },
      ],
      editLink: { baseUrl: undefined },
      lastUpdated: false,
      defaultLocale: 'en',
      // Code blocks are little nooks: dark in both site themes, so there is one
      // syntax theme and no light/dark switch. Colours come from tokens.css
      // (--on-code-*); the var() fallbacks are what Expressive Code measures
      // token contrast against, so keep them equal to the lighter of the two
      // frame backgrounds (the dark site theme's) as the worst case.
      expressiveCode: {
        themes: ['github-dark-default'],
        useStarlightDarkModeSwitch: false,
        useStarlightUiThemeColors: false,
        minSyntaxHighlightingColorContrast: 5.5,
        styleOverrides: {
          borderRadius: '14px',
          borderColor: 'var(--on-code-border, #262d36)',
          codeBackground: 'var(--on-code-bg, #12171e)',
          codeForeground: '#e6edf3',
          codeSelectionBackground: 'rgba(92, 150, 214, 0.32)',
          scrollbarThumbColor: 'rgba(238, 242, 246, 0.14)',
          scrollbarThumbHoverColor: 'rgba(238, 242, 246, 0.28)',
          frames: {
            editorBackground: 'var(--on-code-bg, #12171e)',
            terminalBackground: 'var(--on-code-bg, #12171e)',
            editorTabBarBackground: 'var(--on-code-bar, #0b0e13)',
            editorTabBarBorderColor: 'var(--on-code-border, #262d36)',
            editorTabBorderRadius: '0px',
            editorActiveTabBackground: 'var(--on-code-bg, #12171e)',
            editorActiveTabForeground: '#e6edf3',
            editorActiveTabBorderColor: 'transparent',
            editorActiveTabIndicatorTopColor: 'transparent',
            editorActiveTabIndicatorBottomColor: 'transparent',
            editorActiveTabIndicatorHeight: '0px',
            terminalTitlebarBackground: 'var(--on-code-bar, #0b0e13)',
            terminalTitlebarForeground: 'rgba(230, 237, 243, 0.62)',
            terminalTitlebarBorderBottomColor: 'var(--on-code-border, #262d36)',
            terminalTitlebarDotsForeground: 'rgba(230, 237, 243, 0.42)',
            terminalTitlebarDotsOpacity: '0.6',
            inlineButtonForeground: '#e6edf3',
            inlineButtonBorder: 'rgba(230, 237, 243, 0.24)',
            frameBoxShadowCssValue: 'var(--on-code-shadow, none)',
            tooltipSuccessBackground: '#2f6fb8',
            tooltipSuccessForeground: '#ffffff',
          },
          textMarkers: {
            markBackground: 'rgba(92, 150, 214, 0.16)',
            markBorderColor: 'rgba(92, 150, 214, 0.55)',
          },
        },
      },
      customCss: ['./src/styles/motion.css', './src/styles/custom.css'],
      components: {
        Header: './src/components/Header.astro',
        SiteTitle: './src/components/SiteTitle.astro',
        ThemeSelect: './src/components/ThemeToggle.astro',
        PageTitle: './src/components/PageTitle.astro',
      },
      head: [
        {
          tag: 'link',
          attrs: { rel: 'icon', href: '/favicon.svg', type: 'image/svg+xml' },
        },
        {
          tag: 'link',
          attrs: { rel: 'apple-touch-icon', href: '/apple-touch-icon.png' },
        },
        {
          tag: 'link',
          attrs: { rel: 'preconnect', href: 'https://fonts.googleapis.com' },
        },
        {
          tag: 'link',
          attrs: { rel: 'preconnect', href: 'https://fonts.gstatic.com', crossorigin: '' },
        },
        {
          tag: 'link',
          attrs: {
            rel: 'stylesheet',
            href:
              'https://fonts.googleapis.com/css2?family=Geist:wght@300..700&family=Geist+Mono:wght@400;500&display=swap',
          },
        },
      ],
      sidebar: [
        {
          label: 'Start',
          items: [
            { label: 'Introduction', slug: 'start/introduction' },
            { label: 'Install', slug: 'start/install' },
            { label: 'Your first nook', slug: 'start/first-nook' },
            { label: 'Examples', slug: 'guides/examples' },
          ],
        },
        {
          label: 'Customization',
          items: [
            { label: 'Playground', slug: 'guides/playground' },
            { label: 'Theming', slug: 'guides/theming' },
            { label: 'Surface materials', slug: 'guides/surface-materials' },
            { label: 'Layout and content insets', slug: 'guides/layout-and-insets' },
            { label: 'Settings chrome', slug: 'guides/settings-chrome' },
            { label: 'Chrome customization', slug: 'guides/chrome-customization' },
            { label: 'Companion surfaces', slug: 'guides/companion-surfaces' },
            { label: 'Typing in the nook', slug: 'guides/keyboard' },
            { label: 'Rim glow and edge fade', slug: 'guides/panel-effects' },
            { label: 'Displays and presentation', slug: 'guides/displays' },
          ],
        },
        {
          label: 'Components',
          items: [
            { label: 'File shelf', slug: 'guides/file-shelf' },
            { label: 'Activity queue', slug: 'guides/activity-queue' },
            { label: 'Volume glyph', slug: 'guides/volume-glyph' },
          ],
        },
        {
          label: 'Hosting',
          items: [
            { label: 'Multiple modules', slug: 'guides/multiple-modules' },
          ],
        },
        {
          label: 'Reference',
          items: [
            { label: 'API reference', slug: 'reference/api' },
            { label: 'Shipping', slug: 'guides/shipping' },
            { label: 'Troubleshooting', slug: 'reference/troubleshooting' },
          ],
        },
      ],
    }),
  ],
});
