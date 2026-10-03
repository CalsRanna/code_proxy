import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ListTile + Switch trailing: 点击开关是否双重触发', (tester) async {
    var tileTaps = 0;
    var switchChanges = 0;
    var value = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => ListTile(
              title: const Text('t'),
              trailing: Switch(
                value: value,
                onChanged: (v) {
                  switchChanges++;
                  value = v;
                },
              ),
              onTap: () {
                tileTaps++;
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(tileTaps, 0);
    expect(switchChanges, 1);
    expect(value, isTrue);
  });
}
