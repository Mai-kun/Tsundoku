import 'dart:io';

import 'package:flutter/foundation.dart';
// flutter_agentation 1.0.0 использует legacy-виджеты из package:flutter/material.dart,
// тогда как приложение работает на material_ui (разделение Flutter 3.47+).
// В release-сборке этот модуль отсекается через kDebugMode; в Web WASM —
// через условный экспорт в dev_tools.dart.
// ignore: deprecated_member_use
import 'package:flutter/material.dart' as legacy_material;
import 'package:flutter_agentation/flutter_agentation.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:material_ui/material_ui.dart';

import '../../widgets/media-card/media_card.dart';
import '../ui/button.dart';
import '../ui/popover_menu.dart';
import '../ui/segmented_control.dart';
import '../ui/text_field.dart';

/// Проверяет, относится ли элемент к кастомным интерактивным виджетам Tsundoku
/// для обнаружения в Marionette MCP (`get_interactive_elements`).
@visibleForTesting
bool isTsundokuInteractiveElement(Element element) {
  final Widget widget = element.widget;
  return widget is TsundokuButton ||
      widget is TsundokuSelect ||
      widget is TsundokuPopoverMenu ||
      widget is TsundokuTextField ||
      widget is TsundokuSegmentedControl ||
      widget is MediaCard;
}

/// Извлекает человекочитаемую подпись кастомных виджетов Tsundoku для Marionette.
@visibleForTesting
String? extractTsundokuElementText(Element element) {
  final Widget widget = element.widget;
  if (widget is TsundokuSelect) {
    final String? selected = widget.options
        .where((o) => o.value == widget.value)
        .map((o) => o.label)
        .firstOrNull;
    return widget.label ??
        selected ??
        (widget.placeholder.isNotEmpty ? widget.placeholder : null);
  }
  if (widget is TsundokuPopoverMenu) {
    return widget.label.isNotEmpty ? widget.label : null;
  }
  if (widget is TsundokuTextField) {
    final String? ctrlText = widget.controller?.text;
    if (ctrlText != null && ctrlText.isNotEmpty) return ctrlText;
    return widget.initialValue;
  }
  if (widget is MediaCard) {
    return widget.props.item.title;
  }
  return null;
}

/// Конфигурация Marionette для распознавания кастомного UI-кита Tsundoku.
@visibleForTesting
MarionetteConfiguration buildTsundokuMarionetteConfiguration() {
  return const MarionetteConfiguration(
    isInteractiveElement: isTsundokuInteractiveElement,
    extractText: extractTsundokuElementText,
  );
}

/// Инициализирует [MarionetteBinding] в `kDebugMode` на Desktop и стандартный
/// [WidgetsFlutterBinding] во всех остальных режимах (Release, Android и т.д.).
void ensureAppBindingInitialized() {
  if (kDebugMode &&
      (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
    MarionetteBinding.ensureInitialized(
      buildTsundokuMarionetteConfiguration(),
    );
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }
}

/// Debug-only обёртка Flutter Agentation с legacy `MaterialLocalizations` /
/// `Theme` / `Material`, нужными для `TextField` внутри оверлея поверх
/// `material_ui.MaterialApp`. В release возвращает `null`.
TransitionBuilder? buildDebugAgentationOverlay({bool mcpEnabled = true}) {
  if (!kDebugMode) return null;
  final agentationBuilder = FlutterAgentation.builder(
    appName: 'Tsundoku',
    mcpEnabled: mcpEnabled,
    mcpPort: 4747,
    initialToolbarMinimized: true,
  );
  return (BuildContext context, Widget? child) {
    return Localizations.override(
      context: context,
      delegates: const <LocalizationsDelegate<dynamic>>[
        legacy_material.DefaultMaterialLocalizations.delegate,
      ],
      child: legacy_material.Theme(
        data: legacy_material.ThemeData.dark(),
        child: legacy_material.Material(
          type: legacy_material.MaterialType.transparency,
          child: Builder(
            builder: (ctx) => agentationBuilder(ctx, child),
          ),
        ),
      ),
    );
  };
}
