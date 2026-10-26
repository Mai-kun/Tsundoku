const baseUrl = process.env.TARGET_URL || "http://127.0.0.1:5173";

module.exports = {
  id: "mediatracker_visual",
  viewports: [
    { label: "mobile", width: 390, height: 844 },
    { label: "tablet", width: 768, height: 1024 },
    { label: "desktop", width: 1440, height: 900 },
  ],
  onReadyScript: "backstopOnReady.cjs",
  scenarios: [
    {
      label: "Home View",
      url: `${baseUrl}/?view=home`,
      delay: 400,
      misMatchThreshold: 0.1,
      requireSameDimensions: true,
    },
    {
      label: "Category Game View",
      url: `${baseUrl}/?view=game`,
      delay: 400,
      misMatchThreshold: 0.1,
      requireSameDimensions: true,
    },
    {
      label: "Stats Summary View",
      url: `${baseUrl}/?view=stats`,
      delay: 400,
      misMatchThreshold: 0.1,
      requireSameDimensions: true,
    },
    {
      label: "Lists View",
      url: `${baseUrl}/?view=lists`,
      delay: 400,
      misMatchThreshold: 0.1,
      requireSameDimensions: true,
    },
    {
      label: "History Chronicle View",
      url: `${baseUrl}/?view=history`,
      delay: 400,
      misMatchThreshold: 0.1,
      requireSameDimensions: true,
    },
    {
      label: "Calendar View",
      url: `${baseUrl}/?view=calendar`,
      delay: 400,
      misMatchThreshold: 0.1,
      requireSameDimensions: true,
    },
  ],
  paths: {
    bitmaps_reference: "checks/backstop_data/bitmaps_reference",
    bitmaps_test: "checks/backstop_data/bitmaps_test",
    engine_scripts: "checks",
    html_report: "../reports/backstop_data/html_report",
    ci_report: "../reports/backstop_data/ci_report",
  },
  report: ["browser", "CI"],
  openReport: false,
  engine: "playwright",
  engineOptions: {
    browser: "chromium",
    args: ["--no-sandbox", "--disable-setuid-sandbox"],
  },
  asyncCaptureLimit: 2,
  asyncCompareLimit: 4,
  debug: false,
  debugWindow: false,
};
