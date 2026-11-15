import 'package:material_ui/material_ui.dart';
import 'package:cupertino_ui/cupertino_ui.dart' as cupertino;
import 'package:flutter_test/flutter_test.dart';
import 'package:voice_to_text/shared/app_theme.dart';
import 'package:voice_to_text/settings/settings_shell.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'flat UI keeps adaptive controls and has no backdrop effects: $dark',
      (tester) async {
        var enabled = false;
        Widget app({bool contrast = false}) => MaterialApp(
          theme: auraTheme(dark ? Brightness.dark : Brightness.light),
          builder: auraCupertinoTheme,
          home: MediaQuery(
            data: MediaQueryData(
              highContrast: contrast,
              disableAnimations: true,
            ),
            child: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) => SettingsShell(
                  selected: 0,
                  onSelected: (_) {},
                  status: 'Ready',
                  content: PreferenceGroup(
                    children: [
                      PreferenceRow(
                        icon: Icons.mic,
                        title: 'Microphone',
                        trailing: Switch.adaptive(
                          value: enabled,
                          onChanged: (value) => setState(() => enabled = value),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpWidget(app());
        await tester.pumpAndSettle();
        expect(find.byType(BackdropFilter), findsNothing);
        expect(find.byType(BackdropGroup), findsNothing);
        expect(find.byType(Switch), findsOneWidget);
        final context = tester.element(find.text('Microphone'));
        expect(
          cupertino.CupertinoTheme.of(context).brightness,
          dark ? Brightness.dark : Brightness.light,
        );
        expect(Theme.of(context).inputDecorationTheme.fillColor!.a, 1);
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();
        expect(enabled, isTrue);
        await tester.pumpWidget(app(contrast: true));
        await tester.pumpAndSettle();
        expect(find.byType(BackdropFilter), findsNothing);
        expect(find.text('Microphone'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(tester.binding.hasScheduledFrame, isFalse);
      },
    );
  }
}
