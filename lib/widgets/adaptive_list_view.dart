import 'package:flutter/widgets.dart';

/// A vertical list that wraps short content and fills its available height
/// when the rows overflow. Wrapped content is aligned to the top.
///
/// Give the list a finite height, for example with [Expanded] in a [Column],
/// to enable scrolling. With unbounded height it wraps all rows.
class AdaptiveListView extends StatefulWidget {
  const AdaptiveListView.builder({
    required this.itemCount,
    required this.itemBuilder,
    this.findChildIndexCallback,
    this.padding = EdgeInsets.zero,
    this.reverse = false,
    super.key,
  }) : assert(itemCount >= 0);

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final ChildIndexGetter? findChildIndexCallback;
  final EdgeInsetsGeometry padding;
  final bool reverse;

  @override
  State<AdaptiveListView> createState() => _AdaptiveListViewState();
}

class _AdaptiveListViewState extends State<AdaptiveListView> {
  // Changing shrinkWrap replaces the viewport. Reparent the sliver to keep row
  // state through the switch.
  final _sliverKey = GlobalKey();
  bool _shrinkWrap = true;

  bool _onScrollMetrics(ScrollMetricsNotification notification) {
    if (notification.depth != 0) return false;

    final metrics = notification.metrics;
    final overflow = metrics.maxScrollExtent - metrics.minScrollExtent;
    // Allow a small overflow before expanding, and shrink once it all fits.
    final shrinkWrap = _shrinkWrap ? overflow <= 1 : overflow == 0;
    if (shrinkWrap != _shrinkWrap) {
      setState(() => _shrinkWrap = shrinkWrap);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Align(
      alignment: Alignment.topCenter,
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: _onScrollMetrics,
        child: CustomScrollView(
          reverse: widget.reverse,
          shrinkWrap: _shrinkWrap || !constraints.hasBoundedHeight,
          semanticChildCount: widget.itemCount,
          slivers: [
            SliverPadding(
              padding: widget.padding,
              sliver: SliverList(
                key: _sliverKey,
                delegate: SliverChildBuilderDelegate(
                  widget.itemBuilder,
                  childCount: widget.itemCount,
                  findChildIndexCallback: widget.findChildIndexCallback,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
