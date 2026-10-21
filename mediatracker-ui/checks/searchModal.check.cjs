const { chromium } = require('playwright-core');

const BASE = process.env.TS_BASE || 'http://localhost:5000';
const failures = [];
const pageErrors = [];

function check(name, condition, details) {
  if (!condition) failures.push({ name, details });
  console.log(`${condition ? 'ok   ' : 'FAIL '} ${name}`);
  return condition;
}

/** Opens the category PopoverMenu from a settled dialog and picks the option matching `pattern`. */
async function selectCategoryOption(dialog, page, pattern) {
  const trigger = dialog.locator('button[popovertarget="popover-search-category"]').first();
  await trigger.waitFor({ state: 'visible', timeout: 10000 });
  await trigger.click();
  const menu = page.locator('[popover]:popover-open').first();
  await menu.waitFor({ state: 'visible', timeout: 5000 });
  const option = menu.locator('button[role="option"]', { hasText: pattern }).first();
  await option.click();
  // Picking an option leaves the popover light-dismissable only via Escape/fire-click.
  await page.keyboard.press('Escape');
  await menu.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
}

(async () => {
  const launchOptions = {
    channel: process.env.TS_BROWSER_CHANNEL || (process.platform === 'win32' ? 'msedge' : undefined),
    headless: true
  };
  const browser = await chromium.launch(launchOptions);
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  page.setDefaultTimeout(10000);
  page.on('pageerror', (error) => pageErrors.push(error.message));

  try {
    // 1. The global shortcut opens the native search dialog and focuses its input.
    await page.goto(`${BASE}/?view=home`, { waitUntil: 'domcontentloaded' });
    await page.keyboard.press('Control+k');
    const searchDialog = page.locator('dialog[open]').first();
    await searchDialog.waitFor({ state: 'visible', timeout: 10000 });
    const initialSearchInput = searchDialog.locator('input[type="search"]');
    check('Control+K opens the native search dialog', await searchDialog.evaluate((d) => d instanceof HTMLDialogElement && d.open));
    check('search input receives focus', await initialSearchInput.evaluate((input) => document.activeElement === input));
    await page.keyboard.press('Escape');
    await searchDialog.waitFor({ state: 'hidden' });
    const closedDialog = page.locator('dialog').first();
    check('Escape closes the search dialog', !(await closedDialog.evaluate((d) => d.open)));

    // 2. The header button opens the same dialog.
    await page.locator('dialog[open]').waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
    const headerSearch = page.locator('header button:has(svg), header button:has-text("Ctrl K")').first();
    await headerSearch.click();
    const dialog = page.locator('dialog[open]').first();
    await dialog.waitFor({ state: 'visible', timeout: 10000 });
    check('header search button opens the dialog', await dialog.evaluate((d) => d.open));

    // 3. Search for a stable, recognizable title and inspect one rendered result.
    const searchInput = dialog.locator('input[type="search"]').first();
    await searchInput.fill('Witcher');
    const result = dialog.locator('[role="button"]').first();
    await result.waitFor({ state: 'visible', timeout: 15000 });
    const resultDetails = await result.evaluate((card) => {
      const text = (card.innerText || '').trim();
      const title = card.querySelector('h4, h3, [data-title]');
      const source = [...card.querySelectorAll('span')].some((span) =>
        /anilist|shikimori|myanimelist|kitsu|tmdb|rawg|google books|openlibrary/i.test(span.textContent || ''),
      );
      const cover = !!card.querySelector('img') || [...card.children].some((child) =>
        /bg-canvas/.test(child.className?.toString() || ''),
      );
      const add = [...card.querySelectorAll('button')].some((button) =>
        /^(add|добавить)$/i.test(button.title || button.getAttribute('aria-label') || ''),
      );
      return { text, title: !!title && !!title.textContent?.trim(), source, cover, add };
    });
    check('search renders at least one title result', resultDetails.title, resultDetails);
    check('result shows a source badge', resultDetails.source, resultDetails);
    check('result shows a cover or placeholder', resultDetails.cover, resultDetails);
    check('result has a quick add button', resultDetails.add, resultDetails);

    // 4. Category switching updates the selected category and leaves the dialog usable.
    // The category picker is a PopoverMenu: its trigger opens the popover, an option row selects.
    await selectCategoryOption(dialog, page, /games|игра/i);
    const categoryValue = await dialog
        .locator('button[popovertarget="popover-search-category"]')
        .innerText();
    check('search category switches to Games', /games|игра/i.test(categoryValue), { categoryValue });
    check('dialog remains open after category switch', await dialog.evaluate((d) => d.open));

    // 5. Open result details, wait for its metadata, then dismiss the preview with Escape.
    // Switching back to Anime makes this result type unambiguous for the preview.
    await selectCategoryOption(dialog, page, /anime|аниме/i);
    const animeResult = dialog.locator('[role="button"]').first();
    await animeResult.waitFor({ state: 'visible', timeout: 10000 });
    await animeResult.click();
    const dialogs = page.locator('dialog[open]');
    await page.waitForFunction(() => document.querySelectorAll('dialog[open]').length >= 2, null, { timeout: 10000 });
    const preview = dialogs.nth(1);
    await preview.getByText(/Synopsis|Синопсис/i).waitFor({ state: 'visible', timeout: 10000 });
    const previewText = await preview.innerText();
    check('preview shows synopsis and characteristics', /Synopsis|Синопсис/i.test(previewText) && /Details|Характеристики/i.test(previewText), previewText.slice(0, 500));
    await page.keyboard.press('Escape');
    await preview.waitFor({ state: 'hidden' });
    check('Escape closes the details preview', await page.locator('dialog[open]').count() === 1);
  } catch (error) {
    failures.push({ name: 'unexpected exception', details: error.stack || error.message });
    console.error('EXCEPTION:', error.message);
  } finally {
    if (pageErrors.length) failures.push({ name: 'page errors', details: pageErrors });
    if (pageErrors.length) console.error('PAGE ERRORS:', pageErrors);
    await browser.close();
  }

  if (failures.length) {
    console.error('FAILED:', JSON.stringify(failures, null, 2));
    process.exit(1);
  }
  console.log('OK: search modal open, query, results, categories, and escape behavior all pass');
})().catch((error) => {
  console.error('FATAL:', error);
  process.exit(1);
});
