import js from '@eslint/js';
import globals from 'globals';

export default [
  {
    ignores: [
      'node_modules/',
      'test-results/',
      'playwright-report/',
      'uploads/',
      'public/',
      '__tests__/',
      'tests/',
      'scripts/',
      'playwright.config.js',
      'playwright.e2e.config.js',
      'playwright-global-setup.js',
      'playwright-global-teardown.js',
    ],
  },
  js.configs.recommended,
  {
    languageOptions: {
      ecmaVersion: 2024,
      sourceType: 'module',
      globals: { ...globals.node },
    },
    rules: {
      'no-unused-vars': ['warn', { argsIgnorePattern: '^_' }],
      'no-console': 'off',
      'no-empty': 'warn',
      'no-useless-escape': 'warn',
      'no-control-regex': 'warn',
      'no-const-assign': 'warn',
      'no-undef': 'warn',
      'no-async-promise-executor': 'warn',
    },
  },
];
