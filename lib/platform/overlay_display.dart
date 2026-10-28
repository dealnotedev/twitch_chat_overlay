import 'dart:ui';

/// Win32 desktop coordinates are physical pixels and may have a negative origin.
final class OverlayMonitor {
  const OverlayMonitor({
    required this.id,
    required this.bounds,
    this.primary = false,
  });

  final String id;
  final Rect bounds;
  final bool primary;
}

final class OverlayDisplay {
  const OverlayDisplay({
    required this.bounds,
    required this.scale,
    required this.monitors,
  });

  final Rect bounds;
  final double scale;
  final List<OverlayMonitor> monitors;

  Size get logicalSize => bounds.size / scale;

  OverlayMonitor monitorForId(String id) => monitors.firstWhere(
    (monitor) => monitor.id == id,
    orElse: () => monitors.firstWhere(
      (monitor) => monitor.primary,
      orElse: () => monitors.first,
    ),
  );

  OverlayMonitor monitorForRect(Rect logicalRect) {
    final physicalRect = Rect.fromLTWH(
      bounds.left + logicalRect.left * scale,
      bounds.top + logicalRect.top * scale,
      logicalRect.width * scale,
      logicalRect.height * scale,
    );
    var selected = monitorForId('');
    var largestArea = 0.0;
    for (final monitor in monitors) {
      final overlap = physicalRect.intersect(monitor.bounds);
      final area = overlap.isEmpty ? 0.0 : overlap.width * overlap.height;
      if (area > largestArea) {
        largestArea = area;
        selected = monitor;
      }
    }
    return selected;
  }

  Rect logicalBounds(OverlayMonitor monitor) => Rect.fromLTWH(
    (monitor.bounds.left - bounds.left) / scale,
    (monitor.bounds.top - bounds.top) / scale,
    monitor.bounds.width / scale,
    monitor.bounds.height / scale,
  );

  static OverlayDisplay? fromNative(Object? value) {
    if (value is! Map) return null;
    Rect? readRect(Map raw) {
      final values = [raw['left'], raw['top'], raw['width'], raw['height']];
      if (values.any((v) => v is! num || !v.isFinite)) return null;
      final rect = Rect.fromLTWH(
        (values[0] as num).toDouble(),
        (values[1] as num).toDouble(),
        (values[2] as num).toDouble(),
        (values[3] as num).toDouble(),
      );
      return rect.isEmpty ? null : rect;
    }

    final bounds = readRect(value);
    final scale = value['scale'];
    final rawMonitors = value['monitors'];
    if (bounds == null ||
        scale is! num ||
        !scale.isFinite ||
        scale <= 0 ||
        rawMonitors is! List) {
      return null;
    }
    final monitors = <OverlayMonitor>[];
    for (final raw in rawMonitors) {
      if (raw is! Map) continue;
      final id = raw['id'];
      final rect = readRect(raw);
      if (id is! String || id.isEmpty || rect == null) continue;
      monitors.add(
        OverlayMonitor(id: id, bounds: rect, primary: raw['primary'] == true),
      );
    }
    if (monitors.isEmpty) return null;
    return OverlayDisplay(
      bounds: bounds,
      scale: scale.toDouble(),
      monitors: List.unmodifiable(monitors),
    );
  }
}
