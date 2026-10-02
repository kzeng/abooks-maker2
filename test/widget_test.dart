import 'package:abooks_maker/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the audiobook workspace', (tester) async {
    await tester.pumpWidget(const ABooksMakerApp());

    expect(find.text('有声书工具'), findsOneWidget);
    expect(find.text('导入电子书'), findsOneWidget);
    expect(find.text('转换设置'), findsNothing);

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.text('转换设置'), findsOneWidget);
    expect(find.text('Edge TTS voice'), findsOneWidget);
    expect(find.text('试听当前设置'), findsOneWidget);
  });
}
