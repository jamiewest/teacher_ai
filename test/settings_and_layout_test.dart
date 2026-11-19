import 'package:extensions_flutter/extensions_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teacher_ai/app/app.dart';
import 'package:teacher_ai/app/app_settings.dart';
import 'package:teacher_ai/app/home_shell.dart';
import 'package:teacher_ai/app/service_registration.dart';
import 'package:teacher_ai/app/theme.dart';
import 'package:teacher_ai/data/key_value_store.dart';
import 'package:teacher_ai/data/teacher_workspace.dart';
import 'package:teacher_ai/features/seating/widgets/room_canvas.dart';

import 'seating_page_widget_test.dart' show loadedWorkspace;

Future<void> _pumpWithSettings(
  WidgetTester tester,
  TeacherWorkspace workspace,
  AppSettingsController settings,
  Size size,
) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ListenableBuilder(
      listenable: settings,
      builder: (context, _) => MaterialApp(
        themeMode: settings.settings.themeMode,
        theme: AppTheme.light(settings.settings),
        darkTheme: AppTheme.dark(settings.settings),
        home: HomeShell(workspace: workspace, settings: settings),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('AppSettings and AppSettingsController', () {
    test('round-trips JSON and falls back cleanly on unknown values', () {
      const custom = AppSettings(
        themeMode: ThemeMode.dark,
        colorPreset: AppColorPreset.ocean,
        paletteStyle: PaletteStyle.vibrant,
        canvasStyle: CanvasStyle.highContrast,
        showGridByDefault: false,
        showTagDotsByDefault: false,
      );
      final restored = AppSettings.fromJson(custom.toJson());
      expect(restored, custom);

      final fallback = AppSettings.fromJson({
        'themeMode': 'bogus',
        'colorPreset': 'unknown',
        'paletteStyle': 'missing',
        'canvasStyle': 'invalid',
      });
      expect(fallback, const AppSettings());
    });

    test('persists changes to KeyValueStore and supports resetDefaults', () async {
      final store = InMemoryStore();
      final controller = AppSettingsController(store);
      await controller.load();
      expect(controller.isLoaded, isTrue);
      expect(controller.settings, const AppSettings());

      controller.setThemeMode(ThemeMode.dark);
      controller.setColorPreset(AppColorPreset.plum);
      controller.setPaletteStyle(PaletteStyle.expressive);
      controller.setCanvasStyle(CanvasStyle.highContrast);
      controller.setShowGridByDefault(false);
      controller.setShowTagDotsByDefault(false);
      await testerDelay();

      final reloaded = AppSettingsController(store);
      await reloaded.load();
      expect(reloaded.settings.themeMode, ThemeMode.dark);
      expect(reloaded.settings.colorPreset, AppColorPreset.plum);
      expect(reloaded.settings.paletteStyle, PaletteStyle.expressive);
      expect(reloaded.settings.canvasStyle, CanvasStyle.highContrast);
      expect(reloaded.settings.showGridByDefault, isFalse);
      expect(reloaded.settings.showTagDotsByDefault, isFalse);

      reloaded.resetDefaults();
      expect(reloaded.settings, const AppSettings());

      // Corrupt JSON falls back cleanly without throwing.
      await store.write(AppSettingsController.storageKey, '{bad json');
      final corrupt = AppSettingsController(store);
      await corrupt.load();
      expect(corrupt.settings, const AppSettings());
    });
  });

  group('Settings UI and dynamic theming', () {
    for (final entry in {
      const Size(390, 844): BottomSheet,
      const Size(1400, 900): Dialog,
    }.entries) {
      testWidgets('updates theme, color preset, vibrancy, and canvas on ${entry.key}', (
        tester,
      ) async {
        final workspace = await loadedWorkspace();
        addTearDown(workspace.dispose);
        final settings = AppSettingsController.memory();
        addTearDown(settings.dispose);

        await _pumpWithSettings(tester, workspace, settings, entry.key);

        final canvasElement = tester.element(find.byType(RoomCanvas));
        final lightPalette = RoomPalette.of(canvasElement);
        final tealPrimary = Theme.of(canvasElement).colorScheme.primary;

        await tester.tap(find.byTooltip('Settings'));
        await tester.pumpAndSettle();
        expect(find.byType(entry.value), findsOneWidget);

        await tester.tap(find.text('Dark'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Ocean Blue'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Vibrant'));
        await tester.pumpAndSettle();

        final settingsScrollable = find.descendant(
          of: find.byType(entry.value),
          matching: find.byType(Scrollable),
        );
        await tester.scrollUntilVisible(
          find.text('Projector'),
          200,
          scrollable: settingsScrollable,
        );
        await tester.tap(find.text('Projector'));
        await tester.pumpAndSettle();

        final showGridSwitch = find.widgetWithText(
          SwitchListTile,
          'Show room grid by default',
        );
        await tester.scrollUntilVisible(
          showGridSwitch,
          200,
          scrollable: settingsScrollable,
        );
        await tester.tap(showGridSwitch);
        await tester.pumpAndSettle();

        final updatedElement = tester.element(find.byType(RoomCanvas));
        final darkTheme = Theme.of(updatedElement);
        final darkPalette = RoomPalette.of(updatedElement);
        final editor = tester.widget<RoomCanvas>(find.byType(RoomCanvas)).controller;

        expect(darkTheme.brightness, Brightness.dark);
        expect(darkTheme.colorScheme.primary, isNot(tealPrimary));
        expect(darkPalette.highContrast, isTrue);
        expect(darkPalette.positiveBg, isNot(lightPalette.positiveBg));
        expect(darkPalette.negativeBg, isNot(lightPalette.negativeBg));
        expect(editor.showGrid, isFalse);

        final resetButton = find.text('Reset');
        await tester.tap(resetButton);
        await tester.pumpAndSettle();
        expect(settings.settings, const AppSettings());
        expect(Theme.of(tester.element(find.byType(RoomCanvas))).brightness, Brightness.light);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('TeacherApp loads registered AppSettingsController from DI', (
      tester,
    ) async {
      final store = InMemoryStore();
      final builder = Host.createApplicationBuilder();
      builder.services.addTeacherServices(store: store);
      final host = builder.build();
      addTearDown(host.dispose);

      tester.view
        ..physicalSize = const Size(1280, 800)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(TeacherApp(services: host.services));
      await tester.pumpAndSettle();

      expect(find.byType(HomeShell), findsOneWidget);
      expect(find.byTooltip('Settings'), findsOneWidget);
    });
  });

  group('Canvas-first layout and cross-device responsiveness', () {
    testWidgets('live classroom gives the canvas dominant screen space and true fullscreen', (
      tester,
    ) async {
      final workspace = await loadedWorkspace();
      addTearDown(workspace.dispose);
      final settings = AppSettingsController.memory();
      addTearDown(settings.dispose);

      await _pumpWithSettings(tester, workspace, settings, const Size(390, 844));
      final phoneCanvas = tester.getSize(find.byType(RoomCanvas));
      expect(phoneCanvas.height / 844.0, greaterThan(0.55));

      await tester.tap(find.byTooltip('Expand view'));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsNothing);
      expect(tester.getSize(find.byType(RoomCanvas)).height, 844.0);
      await tester.tap(find.byTooltip('Restore view'));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);

      await _pumpWithSettings(tester, workspace, settings, const Size(1400, 900));
      final desktopCanvas = tester.getSize(find.byType(RoomCanvas));
      expect(desktopCanvas.height / 900.0, greaterThan(0.75));
    });

    for (final size in [
      const Size(320, 640),
      const Size(360, 844),
      const Size(390, 844),
      const Size(844, 390),
      const Size(900, 700),
      const Size(1400, 900),
    ]) {
      testWidgets('all tabs and seating modes render without overflow at $size', (
        tester,
      ) async {
        final workspace = await loadedWorkspace();
        addTearDown(workspace.dispose);
        final settings = AppSettingsController.memory();
        addTearDown(settings.dispose);

        await _pumpWithSettings(tester, workspace, settings, size);
        expect(tester.takeException(), isNull);

        await tester.tap(find.byTooltip('Edit seating'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.tap(find.byTooltip('Design room'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.tap(find.byTooltip('Live classroom'));
        await tester.pumpAndSettle();

        final nav = size.width < 600
            ? find.byType(NavigationBar)
            : find.byType(NavigationRail);
        await tester.tap(
          find.descendant(of: nav, matching: find.text('Roster')),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        if (size.width < 960) {
          await tester.tap(find.text('Tags'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }

        await tester.tap(
          find.descendant(of: nav, matching: find.text('Schedule')),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Inspector auto-save and mobile dialog polish', () {
    testWidgets('desk label and group name commit on blur without pressing Enter', (
      tester,
    ) async {
      final workspace = await loadedWorkspace();
      addTearDown(workspace.dispose);
      final settings = AppSettingsController.memory();
      addTearDown(settings.dispose);

      await _pumpWithSettings(tester, workspace, settings, const Size(1400, 900));
      await tester.tap(find.byTooltip('Design room'));
      await tester.pumpAndSettle();

      final canvas = tester.widget<RoomCanvas>(find.byType(RoomCanvas));
      final editor = canvas.controller;

      // Select first group and edit its name without submitting Enter.
      final group = editor.layout.groups.first;
      editor.selectGroup(group.id);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, group.name),
        'Focus Saved Group',
      );
      // Tap unobstructed empty canvas space to blur the text field.
      await tester.tapAt(
        tester.getTopRight(find.byType(RoomCanvas)) + const Offset(-24, 24),
      );
      await tester.pumpAndSettle();
      expect(editor.layout.groupById(group.id)!.name, 'Focus Saved Group');

      // Select a single desk and edit its label without submitting Enter.
      final desk = editor.layout.seats.first;
      editor.selectOnly(desk.id);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Label'),
        'Window Desk',
      );
      await tester.tapAt(
        tester.getTopRight(find.byType(RoomCanvas)) + const Offset(-24, 24),
      );
      await tester.pumpAndSettle();
      expect(editor.layout.deskById(desk.id)!.label, 'Window Desk');
      await tester.pump(TeacherWorkspace.saveDebounce);
    });

    testWidgets('roster FAB adapts between Students and Tags tabs and uses fullscreen dialog on phone', (
      tester,
    ) async {
      final workspace = await loadedWorkspace();
      addTearDown(workspace.dispose);
      final settings = AppSettingsController.memory();
      addTearDown(settings.dispose);

      await _pumpWithSettings(tester, workspace, settings, const Size(390, 844));
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Roster'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Add student'), findsOneWidget);
      expect(find.byTooltip('New tag'), findsNothing);

      await tester.tap(find.byTooltip('Add student'));
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate((w) => w is Dialog && w.insetPadding == EdgeInsets.zero),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Cancel'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Tags'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('New tag'), findsOneWidget);
      expect(find.byTooltip('Add student'), findsNothing);
    });
  });
}

Future<void> testerDelay() => Future<void>.delayed(Duration.zero);
