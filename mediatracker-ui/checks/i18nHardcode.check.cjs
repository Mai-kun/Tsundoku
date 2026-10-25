const fs = require('fs');
const path = require('path');

// shortcut: Pre-existing legacy files with hardcoded Russian comments or templates pending dedicated localization passes.
// When a component or view is fully migrated to i18n, remove it from this list.
const LEGACY_ALLOWLIST = new Set([
  'src/entities/media/model/detailedScore.ts',
  'src/entities/media/model/dropReasons.ts',
  'src/entities/media/model/genreLabel.ts',
  'src/entities/media/model/timeBudget.ts',
  'src/entities/media/ui/MediaPoster.svelte',
  'src/features/create-media/CreateModal.svelte',
  'src/features/lists/CreateListModal.svelte',
  'src/features/prefetch-details/externalDetailPrefetch.ts',
  'src/features/prefetch-details/mediaDetailPrefetch.ts',
  'src/features/search-external/SearchModal.svelte',
  'src/features/settings/SettingsModal.svelte',
  'src/features/stale-triage/StaleBacklogModal.svelte',
  'src/shared/api/api.ts',
  'src/shared/api/jobsClient.svelte.ts',
  'src/shared/types/models.ts',
  'src/shared/ui/CircularCounter.svelte',
  'src/shared/ui/ImageLightbox.svelte',
  'src/shared/ui/MediaCoverPlaceholder.svelte',
  'src/shared/ui/Modal.svelte',
  'src/shared/utils/historyFormatters.ts',
  'src/views/CalendarView.svelte',
  'src/views/CategoryView.svelte',
  'src/views/HistoryView.svelte',
  'src/views/HomeView.svelte',
  'src/views/ListsView.svelte',
  'src/views/MediaDetailView.svelte',
  'src/widgets/layout/BackgroundJobsModal.svelte',
  'src/widgets/media-card/MangaCard.svelte',
  'src/widgets/media-detail/DetailHeader.svelte',
  'src/widgets/media-detail/DetailSidebar.svelte',
  'src/widgets/media-detail/ExternalDetailModal.svelte',
  'src/widgets/media-detail/FillMissingModal.svelte',
  'src/widgets/media-detail/ProgressStepper.svelte',
  'src/widgets/media-detail/RelationLoadButton.svelte',
  'src/widgets/media-detail/RelinkSourceModal.svelte',
  'src/widgets/media-detail/detailFormatters.ts',
  'src/widgets/media-detail/panels/RelatedPanel.svelte',
  'src/widgets/media-detail/relatedMatching.ts',
  'src/widgets/media-detail/sections/BookEditionSection.svelte',
  'src/widgets/media-detail/sections/BookProgressSection.svelte',
  'src/widgets/media-detail/sections/CastSection.svelte',
  'src/widgets/media-detail/sections/CreatorSection.svelte',
  'src/widgets/media-detail/sections/GameDetailSection.svelte',
  'src/widgets/media-detail/sections/MangaProgressSection.svelte',
  'src/widgets/media-detail/sections/MovieStatusSection.svelte',
  'src/widgets/media-detail/sections/QuickFactsSection.svelte',
  'src/widgets/media-detail/sections/TvShowDetailSection.svelte',
  'src/widgets/media-detail/sections/TvShowProgressSection.svelte',
  'src/widgets/media-detail/tabs/OverviewTab.svelte',
  'src/widgets/stats/TopGenresBar.svelte',
  'src/widgets/stats/taste-profile/DropAnalyticsCard.svelte',
]);

const ROOT = path.resolve(__dirname, '..');
const SRC = path.join(ROOT, 'src');
const CYRILLIC_REGEX = /[\u0400-\u04FF]/;

function walkDir(dir, fileList = []) {
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walkDir(fullPath, fileList);
    } else if (entry.isFile()) {
      if ((entry.name.endsWith('.svelte') || entry.name.endsWith('.ts')) &&
          !entry.name.endsWith('.d.ts') &&
          entry.name !== 'translations.ts') {
        fileList.push(fullPath);
      }
    }
  }
  return fileList;
}

const files = walkDir(SRC);
let errorsCount = 0;
let checkedFilesCount = 0;
let skippedLegacyCount = 0;

console.log(`[check:i18n] Scanning ${files.length} source files in src/ for hardcoded Cyrillic...`);

for (const filePath of files) {
  const relPath = path.relative(ROOT, filePath).replace(/\\/g, '/');

  if (LEGACY_ALLOWLIST.has(relPath)) {
    skippedLegacyCount++;
    continue;
  }

  checkedFilesCount++;
  const content = fs.readFileSync(filePath, 'utf-8');
  const lines = content.split('\n');

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (CYRILLIC_REGEX.test(line)) {
      const match = line.match(/[\u0400-\u04FF]+/g);
      console.error(`[check:i18n FAIL] ${relPath}:${i + 1}: Found Cyrillic text "${match ? match.join(' ') : ''}"`);
      console.error(`   Line: ${line.trim()}`);
      errorsCount++;
    }
  }
}

console.log(`[check:i18n] Checked ${checkedFilesCount} files (skipped ${skippedLegacyCount} legacy allowlisted files).`);

if (errorsCount > 0) {
  console.error(`\n❌ [check:i18n] Failed with ${errorsCount} hardcoded Cyrillic occurrence(s)!`);
  process.exit(1);
} else {
  console.log('✅ [check:i18n] Passed! No hardcoded Cyrillic found in verified files.');
  process.exit(0);
}
