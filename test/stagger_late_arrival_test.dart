import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_brew/theme/tokens.dart';
import 'package:quick_brew/widgets/stagger.dart';

/// Content that arrives after a screen's entrance has finished still plays the
/// entrance, rather than appearing at full opacity on the frame it lands.
void main() {
  /// The opacity the named text is currently being drawn at, as the product of
  /// every Opacity above it.
  double opacityOf(WidgetTester tester, String text) {
    final target = find.text(text);
    expect(target, findsOneWidget, reason: '"$text" should be on screen');
    return tester
        .widgetList<Opacity>(
          find.ancestor(of: target, matching: find.byType(Opacity)),
        )
        .fold<double>(1, (total, layer) => total * layer.opacity);
  }

  /// A group whose item count grows, the way every Firestore-backed panel's does.
  Widget group(int itemCount, List<String> labels) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(),
        child: StaggerGroup(
          itemCount: itemCount,
          reveal: true,
          reduced: false,
          child: Column(
            children: [
              for (final (index, label) in labels.indexed)
                StaggerItem(index: index, child: Text(label)),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('a row that lands after the group has finished still fades in', (
    tester,
  ) async {
    await tester.pumpWidget(group(2, const ['header', 'headline']));

    // Run the whole entrance out, the way a round trip to Firestore does.
    await tester.pump(const Duration(seconds: 2));
    expect(opacityOf(tester, 'header'), 1);

    // The board lands: two more items, and the group's own timeline is spent.
    await tester.pumpWidget(group(4, const ['header', 'headline', 'row', 'row2']));
    await tester.pump();

    expect(
      opacityOf(tester, 'row'),
      lessThan(0.1),
      reason: 'a late row starts from nothing, not from fully drawn',
    );
    expect(
      opacityOf(tester, 'header'),
      1,
      reason: 'the header the reader has been looking at must not re-animate',
    );

    // Halfway through its own 260ms ramp.
    await tester.pump(BrewMotion.staggerItem ~/ 2);
    final midway = opacityOf(tester, 'row');
    expect(midway, greaterThan(0.1));
    expect(midway, lessThan(0.95));

    await tester.pump(BrewMotion.staggerItem);
    expect(opacityOf(tester, 'row'), 1);
    expect(opacityOf(tester, 'row2'), 1);
  });

  testWidgets('rows present from the start ride the group, not their own ramp', (
    tester,
  ) async {
    await tester.pumpWidget(group(3, const ['a', 'b', 'c']));
    await tester.pump();

    // Item 0 opens immediately; the ones behind it are still held back by the
    // 60ms step, which is the group's timeline doing the work.
    expect(opacityOf(tester, 'c'), 0);
    await tester.pump(const Duration(milliseconds: 30));
    expect(opacityOf(tester, 'a'), greaterThan(0));
    expect(opacityOf(tester, 'c'), 0);

    await tester.pump(const Duration(seconds: 2));
    expect(opacityOf(tester, 'c'), 1);
  });
}
