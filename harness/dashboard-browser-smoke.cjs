#!/usr/bin/env node
/**
 * Browser smoke for OPA Dashboard panels (CommonJS for Playwright image).
 * Visits every SideRail route; asserts #root mounts and no blank fatal page.
 * Exit 0 = pass; 2 = soft-only; 1 = hard fail.
 */
const { chromium } = require('playwright');

const DASH = process.env.DASH_HTTP || 'http://127.0.0.1:8088';
const ROUTES = [
  // Service only — Overview removed. Perf Lab browser UX owned by sibling — API smoke only here.
  '/services', '/catalog', '/key-transactions', '/commands', '/traces',
  '/profiling', '/errors', '/logs', '/alerts', '/slos', '/anomalies',
  '/synthetics', '/security', '/diagnostics', '/sql', '/http', '/service-map',
  '/network', '/rum', '/performance', '/compare', '/infrastructure',
  '/cloud', '/metrics', '/query', '/dashboards', '/live', '/serverless',
  '/collaborate', '/system', '/users', '/api-keys', '/automation', '/federation',
];

async function main() {
  let hard = 0;
  let soft = 0;
  let pass = 0;
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage();
  const consoleErrors = [];
  page.on('console', (msg) => {
    if (msg.type() === 'error') consoleErrors.push(msg.text());
  });
  page.on('pageerror', (err) => consoleErrors.push(String(err)));

  for (const route of ROUTES) {
    consoleErrors.length = 0;
    const url = `${DASH}${route}`;
    try {
      const resp = await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 25000 });
      const status = resp ? resp.status() : 0;
      if (status !== 200) {
        console.log(`FAIL ${route} HTTP ${status}`);
        hard++;
        continue;
      }
      await page.waitForSelector('#root', { timeout: 12000 });
      await page.waitForTimeout(900);
      const text = (await page.locator('body').innerText().catch(() => '')) || '';
      const blankFatal =
        /Something went wrong|Application error|ChunkLoadError/i.test(text) && text.length < 500;
      const chromeCount = await page.locator('.opa-rail, .opa-page-title, .opa-page-head, nav').count();
      const hasChrome = chromeCount > 0 || /Open Profiling|Service|Perf lab|Traces|Security/i.test(text);
      const fatalConsole = consoleErrors.filter((e) =>
        /ChunkLoadError|Unexpected token|is not defined|Cannot read prop/i.test(e),
      );
      if (blankFatal) {
        console.log(`FAIL ${route} blank/fatal UI`);
        hard++;
      } else if (!hasChrome) {
        console.log(`SOFT ${route} weak chrome markers`);
        soft++;
      } else if (fatalConsole.length) {
        console.log(`SOFT ${route} console: ${fatalConsole[0].slice(0, 140)}`);
        soft++;
      } else {
        console.log(`OK   ${route}`);
        pass++;
      }
    } catch (e) {
      console.log(`FAIL ${route} ${e.message}`);
      hard++;
    }
  }

  await browser.close();
  console.log(`browser-smoke summary pass=${pass} soft=${soft} fail=${hard}`);
  if (hard > 0) process.exit(1);
  if (soft > 0) process.exit(2);
  process.exit(0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
