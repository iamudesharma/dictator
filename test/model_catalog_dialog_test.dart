import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_to_text/settings/model_catalog_dialog.dart';
import 'package:voice_to_text/shared/app_theme.dart';
import 'package:voice_to_text/transcription/gguf_catalog.dart';

void main() {
  for (final width in [680.0, 960.0]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('full model browser works at $width / $scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        String? selected;
        await tester.pumpWidget(
          MaterialApp(
            theme: auraTheme(Brightness.dark),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    selected = await showDialog<String>(
                      context: context,
                      builder: (_) => const ModelCatalogDialog(
                        selected: 'parakeet_unified_english',
                        imported: {'custom-fixture': 'Imported model'},
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(ggufCatalog, hasLength(18));
        for (final model in ggufCatalog) {
          expect(
            find.byKey(ValueKey('catalog-option-${model.id}')),
            findsOneWidget,
          );
          expect(find.text(model.name), findsOneWidget);
        }
        expect(find.text('Imported model'), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('catalog-search')),
          'qwen',
        );
        await tester.pumpAndSettle();
        expect(find.byType(ListTile), findsNWidgets(2));
        expect(find.text('Qwen3 ASR 0.6B'), findsOneWidget);
        expect(find.text('QwenCleo ASR 1.7B'), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('catalog-search')),
          '',
        );
        await tester.pumpAndSettle();
        expect(find.byType(ListTile), findsNWidgets(19));
        final lastModel = find.byKey(const ValueKey('catalog-option-whisper'));
        await tester.ensureVisible(lastModel);
        await tester.pumpAndSettle();
        await tester.tap(lastModel);
        await tester.pumpAndSettle();
        expect(selected, 'whisper');
        expect(find.byType(ModelCatalogDialog), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
