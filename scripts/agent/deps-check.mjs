// The new-dependency gate: every package version a range adds to pnpm-lock.yaml (direct or transitive) is judged
// on what it is, before any advisory exists for it. Offline: the lockfile from git and the installed package.json.
//   node scripts/agent/deps-check.mjs <base>..<head>   # pre-push and CI (check 2), through gates.sh
// It fails on: an install script (preinstall, install, postinstall) the repo has not allowed in
// pnpm.onlyBuiltDependencies; a new name one edit from a popular package (a typo-squat); a licence outside
// DEPS_LICENSES. A dated row in DEPS_EXCEPTIONS lets one package past one check. Exit 0 pass, 1 fail, 2 usage.
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

// Popular npm names (2026-10): a NEW package one letter from one is a likely typo-squat. Extend it in friday.
const POPULAR = [
  'react',
  'react-dom',
  'react-router',
  'react-router-dom',
  'react-redux',
  'redux',
  'redux-thunk',
  'redux-saga',
  'reselect',
  'immer',
  'zustand',
  'jotai',
  'recoil',
  'mobx',
  'next',
  'nuxt',
  'vue',
  'vue-router',
  'vuex',
  'pinia',
  'svelte',
  'angular',
  'preact',
  'solid-js',
  'lodash',
  'lodash-es',
  'underscore',
  'ramda',
  'axios',
  'node-fetch',
  'cross-fetch',
  'isomorphic-fetch',
  'ky',
  'got',
  'superagent',
  'request',
  'express',
  'koa',
  'fastify',
  'hapi',
  'cors',
  'helmet',
  'morgan',
  'body-parser',
  'cookie-parser',
  'dotenv',
  'dotenv-expand',
  'cross-env',
  'chalk',
  'colors',
  'debug',
  'commander',
  'yargs',
  'minimist',
  'inquirer',
  'prompts',
  'ora',
  'glob',
  'globby',
  'rimraf',
  'mkdirp',
  'fs-extra',
  'chokidar',
  'semver',
  'uuid',
  'nanoid',
  'classnames',
  'clsx',
  'tailwindcss',
  'tailwind-merge',
  'postcss',
  'autoprefixer',
  'sass',
  'less',
  'styled-components',
  'emotion',
  'moment',
  'dayjs',
  'date-fns',
  'luxon',
  'numeral',
  'validator',
  'yup',
  'zod',
  'joi',
  'ajv',
  'formik',
  'react-hook-form',
  'typescript',
  'tslib',
  'eslint',
  'prettier',
  'stylelint',
  'husky',
  'lint-staged',
  'webpack',
  'webpack-cli',
  'rollup',
  'esbuild',
  'vite',
  'parcel',
  'babel-loader',
  'css-loader',
  'style-loader',
  'file-loader',
  'url-loader',
  'ts-loader',
  'html-webpack-plugin',
  'terser',
  'uglify-js',
  'jest',
  'vitest',
  'mocha',
  'chai',
  'sinon',
  'cypress',
  'playwright',
  'puppeteer',
  'supertest',
  'nock',
  'msw',
  'storybook',
  'jquery',
  'bootstrap',
  'antd',
  'd3',
  'chart.js',
  'recharts',
  'echarts',
  'three',
  'socket.io',
  'socket.io-client',
  'ws',
  'graphql',
  'apollo-client',
  'firebase',
  'mongoose',
  'mongodb',
  'mysql',
  'mysql2',
  'pg',
  'sequelize',
  'prisma',
  'typeorm',
  'knex',
  'redis',
  'ioredis',
  'jsonwebtoken',
  'bcrypt',
  'bcryptjs',
  'crypto-js',
  'passport',
  'multer',
  'sharp',
  'jimp',
  'cheerio',
  'jsdom',
  'marked',
  'markdown-it',
  'highlight.js',
  'prismjs',
  'dompurify',
  'sanitize-html',
  'xss',
  'qs',
  'query-string',
  'path-to-regexp',
  'history',
  'i18next',
  'react-i18next',
  'intl',
  'formatjs',
  'framer-motion',
  'gsap',
  'swiper',
  'slick-carousel',
  'react-slick',
  'react-select',
  'react-table',
  'react-query',
  'swr',
  'graphql-request',
  'immutable',
  'rxjs',
  'async',
  'bluebird',
  'core-js',
  'regenerator-runtime',
  'whatwg-fetch',
  'buffer',
  'process',
  'events',
  'stream-browserify',
  'crypto-browserify',
  'util',
  'path-browserify',
  'os-browserify',
  'string_decoder',
  'punycode',
  'url',
  'querystring',
  'http-proxy-middleware',
  'webpack-dev-server',
  'nodemon',
  'concurrently',
  'npm-run-all',
  'pm2',
  'serve',
  'http-server',
  'compression',
  'serve-static',
  'mime',
  'mime-types',
  'form-data',
  'formidable',
  'busboy',
  'archiver',
  'adm-zip',
  'tar',
  'yaml',
  'js-yaml',
  'toml',
  'ini',
  'xml2js',
  'fast-xml-parser',
  'papaparse',
  'xlsx',
  'exceljs',
  'pdfkit',
  'jspdf',
  'html2canvas',
  'qrcode',
  'canvas',
  'electron',
  'react-native',
  'expo',
  'capacitor',
  'cordova',
  'ionic',
];
const range = process.argv[2] ?? '';
if (!/^[^.\s]+\.\.[^.\s]+$/.test(range)) {
  console.error('usage: deps-check.mjs <base>..<head>');
  process.exit(2);
}
const [base, head] = range.split('..');
const env = process.env;
const LOCK = 'pnpm-lock.yaml';
const OWN_SCOPE = env.DEPS_OWN_SCOPE ?? '@therewardstore/';
const licences = new Set(
  (env.DEPS_LICENSES ?? '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean),
);
const exceptionsFile = env.DEPS_EXCEPTIONS ?? 'docs/DEPS-EXCEPTIONS.md';
const maxDays = Number(env.AUDIT_EXCEPTION_MAX_DAYS ?? 90);

const git = (args) => {
  try {
    return execFileSync('git', args, {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
      maxBuffer: 1 << 28,
    });
  } catch {
    return undefined;
  }
};

/** `name@version` for every entry of the lockfile's packages section (v9, and v6's leading slash). */
export function lockPackages(text) {
  const out = new Set();
  let inPackages = false;
  for (const line of (text ?? '').split('\n')) {
    if (/^\S/.test(line)) inPackages = line.startsWith('packages:');
    if (!inPackages) continue;
    const m = /^ {2}'?\/?((?:@[^/@'\s]+\/)?[^@'\s]+)@([^:'(\s]+)/.exec(line);
    if (m) out.add(`${m[1]}@${m[2]}`);
  }
  return out;
}

/** Levenshtein distance capped at 2, for the typo-squat check. */
export function near(a, b) {
  if (Math.abs(a.length - b.length) > 1) return 2;
  let prev = Array.from({ length: b.length + 1 }, (_, i) => i);
  for (let i = 1; i <= a.length; i++) {
    const cur = [i];
    for (let j = 1; j <= b.length; j++) {
      cur[j] = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
    }
    prev = cur;
  }
  return Math.min(prev[b.length], 2);
}

/** True when an SPDX expression is satisfied by the allowed licences (any side of OR, every side of AND). */
export function licenceAllowed(expr, allowed) {
  const clean = String(expr ?? '')
    .replace(/[()]/g, ' ')
    .trim();
  if (!clean) return false;
  return clean
    .split(/\s+OR\s+/i)
    .some((alt) =>
      alt.split(/\s+AND\s+/i).every((id) => allowed.has(id.trim().replace(/\+$/, ''))),
    );
}

function readPackage(dir, map) {
  const pj = join(dir, 'package.json');
  if (!existsSync(pj)) return;
  try {
    const pkg = JSON.parse(readFileSync(pj, 'utf8'));
    const key = `${pkg.name}@${pkg.version}`;
    if (pkg.name && pkg.version && !map.has(key)) map.set(key, pkg);
  } catch {
    /* non-fatal */
  }
}

function listDirs(dir) {
  try {
    return readdirSync(dir, { withFileTypes: true }).filter((e) => e.isDirectory());
  } catch {
    return [];
  }
}

/** name@version → its installed package.json, from every node_modules under the root (hoisted or isolated). */
function installed() {
  const map = new Map();
  const visit = (dir, depth) => {
    if (depth > 6) return;
    for (const e of listDirs(dir)) {
      const p = join(dir, e.name);
      if (e.name.startsWith('@')) visit(p, depth);
      else if (e.name === '.pnpm' || e.name === 'node_modules') visit(p, depth + 1);
      else {
        readPackage(p, map);
        if (existsSync(join(p, 'node_modules'))) visit(join(p, 'node_modules'), depth + 1);
      }
    }
  };
  visit('node_modules', 0);
  return map;
}

function allowedBuilds() {
  const names = new Set();
  try {
    for (const n of JSON.parse(readFileSync('package.json', 'utf8')).pnpm?.onlyBuiltDependencies ??
      [])
      {names.add(n);}
  } catch {
    /* non-fatal */
  }
  if (existsSync('pnpm-workspace.yaml')) {
    const text = readFileSync('pnpm-workspace.yaml', 'utf8');
    const block = /^onlyBuiltDependencies:\s*\n((?:\s+-.*\n?)+)/m.exec(text);
    for (const m of block?.[1].matchAll(/-\s*['"]?([^'"\s]+)/g) ?? []) names.add(m[1]);
  }
  return names;
}

/** Rows `| package | check | until | why |`; a row past its date, or further than maxDays away, does not count. */
function exceptions() {
  const out = [];
  if (!existsSync(exceptionsFile)) return out;
  const today = new Date().toISOString().slice(0, 10);
  const limit = new Date(Date.now() + maxDays * 86_400_000).toISOString().slice(0, 10);
  for (const line of readFileSync(exceptionsFile, 'utf8').split('\n')) {
    const cells = line.split('|').map((c) => c.trim().replace(/^`|`$/g, ''));
    if (cells.length < 5 || !/^\d{4}-\d{2}-\d{2}$/.test(cells[3])) continue;
    if (cells[3] < today || cells[3] > limit || !cells[4]) continue;
    out.push({ pkg: cells[1], check: cells[2] });
  }
  return out;
}

if (!git(['diff', '--name-only', range, '--', LOCK])?.trim()) {
  console.log('▸ new dependencies: pnpm-lock.yaml did not change');
  process.exit(0);
}
const before = lockPackages(git(['show', `${base}:${LOCK}`]));
const after = lockPackages(
  git(['show', `${head}:${LOCK}`]) ?? (existsSync(LOCK) ? readFileSync(LOCK, 'utf8') : ''),
);
const namesBefore = new Set([...before].map((k) => k.slice(0, k.lastIndexOf('@'))));
const added = [...after].filter((k) => !before.has(k));
if (!added.length) {
  console.log('▸ new dependencies: none added');
  process.exit(0);
}
const popular = new Set(POPULAR);
const pkgs = installed();
const builds = allowedBuilds();
const excused = exceptions();
const isExcused = (key, name, check) =>
  excused.some((e) => (e.pkg === name || e.pkg === key) && e.check === check);
const problems = [];
const notInstalled = [];
for (const key of added) {
  const name = key.slice(0, key.lastIndexOf('@'));
  if (name.startsWith(OWN_SCOPE)) continue;
  if (!namesBefore.has(name) && !name.startsWith('@') && name.length >= 5 && !popular.has(name)) {
    const twin = [...popular].find((p) => p.length >= 5 && near(name, p) === 1);
    if (twin && !isExcused(key, name, 'name'))
      {problems.push(`${key}: one letter from "${twin}" (a typo-squat?)`);}
  }
  const pkg = pkgs.get(key);
  if (!pkg) {
    notInstalled.push(key);
    continue;
  }
  const scripts = ['preinstall', 'install', 'postinstall'].filter((s) => pkg.scripts?.[s]);
  if (scripts.length && !builds.has(name) && !isExcused(key, name, 'install-script')) {
    problems.push(
      `${key}: runs ${scripts.join(', ')} at install; allow it in pnpm.onlyBuiltDependencies after review`,
    );
  }
  const licence =
    typeof pkg.license === 'string'
      ? pkg.license
      : (pkg.license?.type ?? pkg.licenses?.map((l) => l.type ?? l).join(' OR '));
  if (licences.size && !licenceAllowed(licence, licences) && !isExcused(key, name, 'licence')) {
    problems.push(`${key}: licence "${licence ?? 'none'}" is not in DEPS_LICENSES`);
  }
}
console.log(`▸ new dependencies: ${added.length} package version(s) added`);
// Platform builds of another OS are in the lockfile but not installed here; CI's Linux install checks its own.
if (notInstalled.length)
  {console.log(
    `  not installed here, not judged: ${notInstalled.slice(0, 5).join(', ')}${notInstalled.length > 5 ? ' …' : ''}`,
  );}
if (!problems.length) process.exit(0);
for (const p of problems) console.error(`✖ ${p}`);
console.error(
  `  A reviewed exception: a row in ${exceptionsFile} (package | install-script, licence or name | until | why).`,
);
process.exit(1);
