import 'package:tsundoku_flutter/main.dart';

import 'golden_test_helper.dart';

void main() {
  // Первый smoke-golden каркаса (Этап 0). Эталон — 1440×900, как
  // Svelte-скриншоты из mediatracker-ui/checks/harness (backstop desktop).
  tsundokuGoldenTest(
    'app_scaffold_placeholder',
    const TsundokuApp(),
  );
}
