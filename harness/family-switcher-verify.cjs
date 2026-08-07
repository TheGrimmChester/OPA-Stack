#!/usr/bin/env node
/**
 * NAS family switcher verification — login, ProjectScopeMenu, console errors.
 * Usage: HOST=192.168.100.101 node family-switcher-verify.cjs
 */
const { chromium } = require('playwright');

const HOST = process.env.HOST || '192.168.100.101';
const USER = process.env.SMOKE_USER || 'admin';
const PASS = process.env.SMOKE_PASS || 'admin';

const DASHBOARDS = [
  { key: 'OPA', port: 8088, loginPath: '/login', homePath: '/services', authViaOam: false },
  { key: 'ORA', port: 8089, loginPath: '/login', homePath: '/', authViaOam: true },
  { key: 'OSA', port: 8094, loginPath: '/login', homePath: '/', authViaOam: true },
  { key: 'OPL', port: 8095, loginPath: '/login', homePath: '/', authViaOam: true },
  { key: 'OPM', port: 8098, loginPath: '/login', homePath: '/', authViaOam: true },
  { key: 'OAM', port: 18097, loginPath: '/login', homePath: '/overview', authViaOam: false, oamExtra: true },
];

const BLOCKING_CONSOLE = [
  /Content Security Policy/i,
  /Refused to connect/i,
  /ChunkLoadError/i,
  /Unexpected token/i,
  /is not defined/i,
  /Cannot read propert/i,
  /Failed to fetch dynamically imported module/i,
];

function isBlockingConsole(msg) {
  return BLOCKING_CONSOLE.some((re) => re.test(msg));
}

async function login(page, dash, consoleErrors) {
  const base = `http://${HOST}:${dash.port}`;
  await page.goto(`${base}${dash.loginPath}`, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(800);

  const userField = page.locator('#login-username, input[autocomplete="username"], input[type="text"]').first();
  const passField = page.locator('#login-password, input[autocomplete="current-password"], input[type="password"]').first();
  await userField.fill(USER);
  await passField.fill(PASS);

  const apiCalls = [];
  page.on('request', (req) => {
    const u = req.url();
    if (u.includes('/api/auth/login')) apiCalls.push(u);
  });

  await page.locator('button[type="submit"]').first().click();
  await page.waitForTimeout(2500);

  const token = await page.evaluate(() => localStorage.getItem('auth_token'));
  if (!token) {
    const errText = await page.locator('[role="alert"], .login-error, .oui-banner').first().textContent().catch(() => '');
    throw new Error(`login failed — no token${errText ? `: ${errText.trim()}` : ''}`);
  }

  const loginUrl = apiCalls.find((u) => u.includes('/api/auth/login'));
  if (dash.authViaOam && loginUrl && !loginUrl.includes('/oam-auth/')) {
    throw new Error(`login did not use /oam-auth (got ${loginUrl})`);
  }

  const cspHits = consoleErrors.filter((e) => /Content Security Policy|Refused to connect/i.test(e));
  if (cspHits.length) throw new Error(`CSP on login: ${cspHits[0]}`);

  return token;
}

async function verifySwitcher(page, dash) {
  const base = `http://${HOST}:${dash.port}`;
  await page.goto(`${base}${dash.homePath}`, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForSelector('#root', { timeout: 15000 });
  await page.waitForTimeout(1500);

  const switcher = page.locator('.oui-switcher').first();
  if (!(await switcher.count())) throw new Error('project switcher (.oui-switcher) not found');
  await switcher.click();
  await page.waitForTimeout(400);

  const scopeMenu = page.locator('.oui-project-scope');
  if (!(await scopeMenu.count())) throw new Error('ProjectScopeMenu (.oui-project-scope) not in switcher');

  const projectItems = page.locator('.oui-project-scope-item');
  const projectCount = await projectItems.count();
  if (projectCount === 0) {
    const empty = await page.locator('.oui-project-scope-empty').textContent().catch(() => '');
    throw new Error(`no projects in switcher${empty ? `: ${empty.trim()}` : ''}`);
  }

  const apiBefore = [];
  const onReq = (req) => {
    if (req.url().includes('/api/') && req.method() === 'GET') apiBefore.push(req.url());
  };
  page.on('request', onReq);

  // Single select first project
  await projectItems.first().click();
  await page.waitForTimeout(1200);
  page.off('request', onReq);

  const labelAfterSingle = await page.locator('.oui-switcher-project').textContent().catch(() => '');
  if (/^All projects$/i.test(labelAfterSingle || '')) {
    throw new Error('single-select did not change scope label from All projects');
  }

  // Re-open and multi-select if >=2 projects
  await switcher.click();
  await page.waitForTimeout(300);
  if (projectCount >= 2) {
    await projectItems.nth(1).click();
    await page.waitForTimeout(800);
    const multiLabel = await page.locator('.oui-switcher-project').textContent().catch(() => '');
    if (!/\d+ projects/.test(multiLabel || '') && projectCount > 1) {
      throw new Error(`multi-select label unexpected: "${multiLabel}"`);
    }
  }

  // Back to All
  await switcher.click();
  await page.waitForTimeout(300);
  await page.locator('.oui-project-scope-all').click();
  await page.waitForTimeout(800);
  const allLabel = await page.locator('.oui-switcher-project').textContent().catch(() => '');
  if (!/All projects/i.test(allLabel || '')) {
    throw new Error(`All projects not restored: "${allLabel}"`);
  }

  return { projectCount };
}

async function verifyOamExtras(page, dash) {
  const base = `http://${HOST}:${dash.port}`;

  // Projects matrix page
  await page.goto(`${base}/projects`, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(2000);

  const table = page.locator('table, .oui-table');
  if (!(await table.count())) throw new Error('/projects table not found');

  const productCheckboxes = page.locator('input[type="checkbox"]').filter({ hasNot: page.locator('[disabled]') });
  const cbCount = await productCheckboxes.count();
  if (cbCount === 0) throw new Error('no product toggles on /projects matrix');

  // Select/unselect all controls
  const selectAll = page.getByRole('button', { name: /select all|enable all/i });
  const unselectAll = page.getByRole('button', { name: /unselect all|disable all|clear all/i });
  if (!(await selectAll.count()) && !(await unselectAll.count())) {
    // Soft — may be per-row only
  }

  // Prefer a real /projects/:id link; fall back to Open control.
  const detailHref = await page.locator('a[href*="/projects/"]').first().getAttribute('href').catch(() => null);
  if (detailHref) {
    await page.goto(`${base}${detailHref}`, { waitUntil: 'domcontentloaded', timeout: 30000 });
  } else {
    const openBtn = page.getByRole('button', { name: /^Open$/i }).first();
    if (!(await openBtn.count())) throw new Error('no project detail entry on /projects');
    await openBtn.click();
  }
  await page.waitForTimeout(2500);
  if (!/\/projects\/[^/?#]+/.test(page.url())) {
    throw new Error(`/projects/:id did not open (url=${page.url()})`);
  }
  const copyRows = page.locator('.oam-copy-row');
  if (!(await copyRows.count())) throw new Error('/projects/:id detail copy rows missing');
  const terms = await page.locator('.oam-copy-row__term').allTextContents();
  if (!terms.some((t) => /project\s*id|^id$/i.test(t.trim()))) {
    throw new Error(`/projects/:id missing copyable id field (terms=${JSON.stringify(terms)})`);
  }
}

async function verifyDashboard(browser, dash) {
  const page = await browser.newPage();
  const consoleErrors = [];
  page.on('console', (msg) => {
    if (msg.type() === 'error') consoleErrors.push(msg.text());
  });
  page.on('pageerror', (err) => consoleErrors.push(String(err)));

  const result = { key: dash.key, port: dash.port, pass: false, error: null, projectCount: 0 };

  try {
    await login(page, dash, consoleErrors);
    const sw = await verifySwitcher(page, dash);
    result.projectCount = sw.projectCount;
    if (dash.oamExtra) await verifyOamExtras(page, dash);

    const blocking = consoleErrors.filter(isBlockingConsole);
    if (blocking.length) throw new Error(`blocking console: ${blocking[0].slice(0, 160)}`);

    result.pass = true;
    console.log(`PASS  ${dash.key} :${dash.port} projects=${sw.projectCount}`);
  } catch (e) {
    result.error = e.message;
    console.log(`FAIL  ${dash.key} :${dash.port} — ${e.message}`);
  } finally {
    await page.close();
  }
  return result;
}

async function main() {
  const browser = await chromium.launch({ headless: true });
  const results = [];
  for (const dash of DASHBOARDS) {
    results.push(await verifyDashboard(browser, dash));
  }
  await browser.close();

  const failed = results.filter((r) => !r.pass);
  console.log('\n========== SUMMARY ==========');
  for (const r of results) {
    console.log(`${r.pass ? 'PASS' : 'FAIL'}  ${r.key} http://${HOST}:${r.port}${r.error ? ` — ${r.error}` : ''}`);
  }
  console.log(`TOTAL ${results.filter((r) => r.pass).length}/${results.length} passed`);
  process.exit(failed.length ? 1 : 0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
