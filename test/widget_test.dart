import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stream_app/main.dart';

void main() {
  testWidgets('App boots to home feed with capsule nav', (WidgetTester tester) async {
    await tester.pumpWidget(const StreamApp());
    await tester.pump();

    expect(find.text('Поиск видео...'), findsOneWidget);
    expect(find.byIcon(Icons.home), findsOneWidget);
    expect(find.byIcon(Icons.video_library), findsOneWidget);
    expect(find.byIcon(Icons.grid_view), findsOneWidget);
  });
}
