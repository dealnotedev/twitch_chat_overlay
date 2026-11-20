import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twitch_chat_overlay/widgets/adaptive_list_view.dart';

void main() {
  testWidgets('a forward list adapts to bounded and unbounded height', (
    tester,
  ) async {
    const rowHeight = 24.0;
    const availableHeight = 72.0;

    Future<void> showList(int itemCount, double maxHeight) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minHeight: 0,
            maxHeight: maxHeight,
            child: AdaptiveListView.builder(
              itemCount: itemCount,
              itemBuilder: (context, index) =>
                  SizedBox(height: rowHeight, child: Text('Row $index')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    final scrollView = find.byType(CustomScrollView);
    await showList(2, availableHeight);
    expect(tester.getSize(scrollView).height, 2 * rowHeight);
    expect(tester.getTopLeft(find.text('Row 0')).dy, 0);
    expect(tester.getTopLeft(find.text('Row 1')).dy, rowHeight);

    await showList(4, availableHeight);
    expect(tester.getSize(scrollView).height, availableHeight);
    expect(tester.widget<CustomScrollView>(scrollView).shrinkWrap, isFalse);

    await showList(4, double.infinity);
    expect(tester.getSize(scrollView).height, 4 * rowHeight);
    expect(tester.widget<CustomScrollView>(scrollView).shrinkWrap, isTrue);

    await showList(4, availableHeight);
    expect(tester.getSize(scrollView).height, availableHeight);
    expect(tester.widget<CustomScrollView>(scrollView).shrinkWrap, isFalse);
  });
}
