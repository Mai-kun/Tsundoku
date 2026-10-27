module.exports = async (page, scenario) => {
  // Inject CSS to disable animations, transitions and lock scrollbars for 100% deterministic visual rendering
  await page.addStyleTag({
    content: `
      *, *::before, *::after {
        transition: none !important;
        animation: none !important;
        caret-color: transparent !important;
      }
      ::-webkit-scrollbar {
        display: none !important;
      }
      html, body {
        scrollbar-width: none !important;
      }
    `,
  });

  // Ensure all web fonts are loaded
  await page.evaluate(async () => {
    if (document.fonts) {
      await document.fonts.ready;
    }
  });

  // Wait for loading spinners / skeleton / animate-pulse to detach
  await page
    .waitForSelector(".animate-pulse", { state: "detached", timeout: 10000 })
    .catch(() => {});

  // Stabilize view rendering
  await page.waitForTimeout(300);
};
