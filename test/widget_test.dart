// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:thanks_everyday/main.dart';

void main() {
  testWidgets('Thanks Everyday app smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ThanksEverydayApp());

    // Verify that our main text is displayed.
    expect(find.text('오늘 좋았던 일을\n말해주세요'), findsOneWidget);
    expect(find.text('👆 버튼을 눌러서 말해주세요'), findsOneWidget);

    // Verify that the 3-dot system is displayed
    expect(find.text("오늘의 감사"), findsOneWidget);
    expect(find.text("0/3 완료"), findsOneWidget);

    // Verify that mic and camera icons are present.
    expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
    expect(find.byIcon(Icons.camera_alt_rounded), findsOneWidget);
  });
}