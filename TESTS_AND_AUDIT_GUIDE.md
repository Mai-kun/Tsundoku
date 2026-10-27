# TESTS AND AUDIT GUIDE

This document provides a comprehensive overview of the testing, auditing, and performance verification processes for the MediaTracker project.

## 1. Quick Start

| Command | Description |
| :--- | :--- |
| `npm run fix` | Runs code fixers and formatters. |
| `npm test` | Runs all tests (Unit, Integration, E2E). |
| `npm run audit` | Runs all static, performance, and accessibility checks. |
| `npm run visual` | Executes visual regression testing suite. |
| `npm run security` | Runs security vulnerability scans. |

## 2. Catalog of Checks and Tests

### Static Contours (`checks/static/*`)
- `bundleBudget.check.ts`: Enforces JS/CSS bundle size budgets.
- `contractDrift.check.ts`: Checks for API contract inconsistencies.
- `deslopAndUiMath.check.ts`: AI-based detector for UI bloat and complexity.
- `htmlValidate.check.ts`: Validates HTML structure against standards.
- `i18nHardcode.check.ts`: Finds hardcoded strings missing i18n keys.
- `i18nParity.check.ts`: Ensures all translations exist across languages.
- `leadingChars.check.ts`: Validates leading character constraints.
- `orphanChecks.check.ts`: Detects unused assets/code.
- `stateRaw.check.ts`: Checks for raw state usage in UI components.

### Audit and Profiling (`checks/audit/*`)
- `browserSuite.runner.ts`: Runs browser-based automated tests.
- `cdpProfiler.check.ts`: Profiles performance using Chrome DevTools Protocol.
- `layoutGeometry.check.ts`: Validates layout stability and geometry.
- `axeAccessibility.check.ts`: Accessibility audit using Axe.
- `visualSnapshots.check.ts`: Takes visual snapshots for regression testing.
- `webVitals.check.ts`: Monitors Core Web Vitals.
- `runBackstop.check.ts`: Runs BackstopJS for visual regression.

### E2E Scenarios (`checks/e2e/*`)
- Various files (`cards`, `categorySwitch`, `seasons`, etc.) implementing user journey testing.

### Backend (`MediaTracker.Tests`)
- xUnit-based unit and `WebApplicationFactory` integration tests.

### Frontend (`mediatracker-ui/src/**/__tests__/*`)
- Vitest unit and integration suites.

## 3. Guide to Configuring Rules

### Budgets
- **Bundle Sizes**: Modify `mediatracker-ui/checks/static/bundleBudget.check.ts`.
- **Latency/Performance**: Modify `scripts/measure-api-payloads.mjs` and `mediatracker-ui/checks/audit/cdpProfiler.check.ts`.

### AI De-slop Detector
- Logic resides in `checks/static/deslopAndUiMath.check.ts`.
- Rules are governed by the overarching project configuration and `SKILL.md` instructions.
