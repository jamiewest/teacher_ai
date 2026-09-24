import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../domain/models/models.dart';
import '../../../domain/ops/layout_ops.dart';

/// Shared paint and hit-test geometry for a group's outline and name.
class GroupVisual {
  GroupVisual({required this.group, required this.bounds, required this.label});

  final DeskGroup group;
  final Rect bounds;
  final TextPainter? label;

  RRect get outline =>
      RRect.fromRectAndRadius(bounds, const Radius.circular(24));
  Offset get labelPosition =>
      Offset(bounds.left + 6, bounds.top - (label?.height ?? 0) - 2);
  Rect? get labelBounds => label == null ? null : labelPosition & label!.size;

  bool contains(Offset point) =>
      outline.contains(point) || (labelBounds?.contains(point) ?? false);

  static List<GroupVisual> forLayout(
    RoomLayout layout,
    TextLayoutCache cache,
    double scale,
  ) => [
    for (final group in layout.groups)
      if (layout.desksInGroup(group.id) case final desks when desks.isNotEmpty)
        () {
          final bounds = LayoutOps.boundsOf(desks).inflate(18);
          return GroupVisual(
            group: group,
            bounds: bounds,
            label: scale <= 0.22
                ? null
                : cache.get(
                    group.name,
                    TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Color(group.colorValue),
                    ),
                    bounds.width - 12,
                  ),
          );
        }(),
  ];
}

/// Everything the painter needs about one desk, resolved ahead of paint so the
/// painter never reaches back into services.
class DeskVisual {
  const DeskVisual({
    required this.desk,
    this.studentName,
    this.studentInitials,
    this.tagColors = const <Color>[],
    this.groupColor,
    this.groupName,
    this.isSelected = false,
    this.isPinned = false,
  });

  final Desk desk;

  /// Null when the seat is empty.
  final String? studentName;
  final String? studentInitials;

  /// Colors of the tags on the seated student, capped by the caller.
  final List<Color> tagColors;

  final Color? groupColor;
  final String? groupName;
  final bool isSelected;

  /// Pinned seats survive a shuffle.
  final bool isPinned;
}

/// Reuses laid-out text between frames. Desk labels change rarely but repaint
/// constantly while dragging, and laying out text is the expensive part.
class TextLayoutCache {
  final _entries = <String, TextPainter>{};

  TextPainter get(String text, TextStyle style, double maxWidth) {
    final key =
        '$text|${style.fontSize}|${style.color?.toARGB32()}|'
        '${style.fontWeight?.value}|${maxWidth.round()}';
    return _entries.putIfAbsent(key, () {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: style.copyWith(fontFamily: 'Roboto'),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        maxLines: 2,
        ellipsis: '…',
      )..layout(maxWidth: maxWidth);
      return painter;
    });
  }

  void clear() => _entries.clear();
}

/// Paints the classroom: floor, grid, group halos, and every desk.
///
/// The painter works entirely in **room centimeters** and applies [scale] and
/// [pan] once at the top. That keeps every coordinate in this file in the same
/// units as the saved model, so what is drawn and what is stored cannot drift.
class RoomPainter extends CustomPainter {
  RoomPainter({
    required this.layout,
    required this.visuals,
    required this.palette,
    required this.textCache,
    required this.scale,
    required this.pan,
    this.showGrid = true,
    this.showTags = true,
    this.marquee,
    this.rotationHandle,
    this.showNames = true,
    this.showFacing = true,
    this.selectedGroupId,
  });

  final RoomLayout layout;
  final List<DeskVisual> visuals;
  final RoomPalette palette;
  final TextLayoutCache textCache;

  /// Screen pixels per room centimeter.
  final double scale;

  /// Screen-space translation of the room's origin.
  final Offset pan;

  final bool showGrid;
  final bool showTags;
  final bool showNames;
  final bool showFacing;
  final String? selectedGroupId;

  /// Marquee rectangle in room coordinates, while the user is dragging one.
  final Rect? marquee;

  /// Room-space center of the selected desk or group's rotation handle.
  final Offset? rotationHandle;

  /// Grid lines finer than this many screen pixels are skipped, so zooming out
  /// does not turn the room into a solid block of hairlines.
  static const double _minGridPixels = 6;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..translate(pan.dx, pan.dy)
      ..scale(scale);

    _paintFloor(canvas);
    if (showGrid) _paintGrid(canvas);
    _paintGroups(canvas);
    for (final visual in visuals) {
      _paintDesk(canvas, visual);
    }
    if (marquee != null) _paintMarquee(canvas, marquee!);
    if (rotationHandle != null) _paintRotationHandle(canvas, rotationHandle!);

    canvas.restore();
  }

  void _paintFloor(Canvas canvas) {
    final rect = Rect.fromLTWH(0, 0, layout.roomWidth, layout.roomHeight);
    canvas
      ..drawRect(rect, Paint()..color = palette.floor)
      ..drawRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 / scale
          ..color = palette.wall,
      );
  }

  void _paintGrid(Canvas canvas) {
    final step = layout.gridSize;
    if (step <= 0) return;

    // Skip the fine grid when it would alias into mush.
    final drawMinor = step * scale >= _minGridPixels;
    final minor = Paint()
      ..color = palette.gridLine
      ..strokeWidth = 1 / scale;
    final major = Paint()
      ..color = palette.gridLineMajor
      ..strokeWidth = 1.5 / scale;

    // A major line every metre gives a sense of real-world scale.
    const majorEvery = 100.0;

    for (var x = 0.0; x <= layout.roomWidth; x += step) {
      final isMajor = (x % majorEvery).abs() < 0.01;
      if (!isMajor && !drawMinor) continue;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, layout.roomHeight),
        isMajor ? major : minor,
      );
    }
    for (var y = 0.0; y <= layout.roomHeight; y += step) {
      final isMajor = (y % majorEvery).abs() < 0.01;
      if (!isMajor && !drawMinor) continue;
      canvas.drawLine(
        Offset(0, y),
        Offset(layout.roomWidth, y),
        isMajor ? major : minor,
      );
    }
  }

  /// Draws a tinted halo behind each group so pods read as teams at a glance.
  void _paintGroups(Canvas canvas) {
    for (final visual in GroupVisual.forLayout(layout, textCache, scale)) {
      final group = visual.group;
      final selected = group.id == selectedGroupId;
      final color = Color(group.colorValue);

      canvas
        ..drawRRect(
          visual.outline,
          Paint()..color = color.withValues(alpha: selected ? 0.22 : 0.12),
        )
        ..drawRRect(
          visual.outline,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = (selected ? 3 : 1.5) / scale
            ..color = selected
                ? palette.selection
                : color.withValues(alpha: 0.55),
        );

      // Group names are only legible past a certain zoom; below it the halo
      // colour alone carries the grouping.
      visual.label?.paint(canvas, visual.labelPosition);
    }
  }

  void _paintDesk(Canvas canvas, DeskVisual visual) {
    final desk = visual.desk;
    canvas
      ..save()
      ..translate(desk.x, desk.y)
      ..rotate(desk.rotation * math.pi / 180.0);

    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: desk.width,
      height: desk.height,
    );
    final path = _shapePath(rect, desk.shape);

    final baseFill = desk.isSeat ? palette.deskFill : palette.fixtureFill;
    final fill = visual.groupColor == null
        ? baseFill
        : Color.alphaBlend(
            visual.groupColor!.withValues(alpha: 0.18),
            baseFill,
          );

    canvas.drawPath(path, Paint()..color = fill);

    final isEmptySeat = desk.isSeat && visual.studentName == null;
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = (visual.isSelected ? 3 : 1.5) / scale
      ..color = visual.isSelected
          ? palette.selection
          : (desk.isSeat ? palette.deskBorder : palette.fixtureBorder);

    if (isEmptySeat && !visual.isSelected) {
      _drawDashedPath(canvas, path, borderPaint, dash: 10, gap: 7);
    } else {
      canvas.drawPath(path, borderPaint);
    }

    // A chevron on the leading edge shows which way the student is facing;
    // the desk body rotates, but the label below stays upright to stay legible.
    if (desk.isSeat && showFacing) _paintFacingChevron(canvas, rect);

    canvas.restore();

    if (desk.locked) _paintLockBadge(canvas, desk);
    if (visual.isPinned) _paintPinBadge(canvas, desk);
    if (showNames) _paintDeskLabel(canvas, visual);
  }

  void _paintFacingChevron(Canvas canvas, Rect rect) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5 / scale
      ..strokeCap = StrokeCap.round
      ..color = palette.emptySeat.withValues(alpha: 0.65);
    final y = rect.top + 7;
    final half = math.min(rect.width * 0.18, 12.0);
    canvas.drawPath(
      Path()
        ..moveTo(-half, y + half * 0.6)
        ..lineTo(0, y - half * 0.2)
        ..lineTo(half, y + half * 0.6),
      paint,
    );
  }

  /// Desk text is drawn unrotated in room space: a teacher reads the chart
  /// from one orientation, so upside-down names help nobody.
  void _paintDeskLabel(Canvas canvas, DeskVisual visual) {
    final desk = visual.desk;
    final useInitials = scale < 0.5 && visual.studentInitials != null;
    final label =
        (useInitials ? visual.studentInitials : visual.studentName) ??
        (desk.label.isNotEmpty ? desk.label : null);
    final maxWidth = desk.isSeat
        ? desk.bounds.width - 8
        : math.max(desk.width, desk.height) - 8;

    if (label == null) {
      if (!desk.isSeat || scale < 0.25) return;
      final painter = textCache.get(
        scale < 0.5 ? '+' : 'Empty',
        TextStyle(
          fontSize: (10 / scale).clamp(13, 19),
          color: palette.emptySeat.withValues(alpha: 0.7),
          fontWeight: FontWeight.w400,
        ),
        maxWidth,
      );
      painter.paint(
        canvas,
        Offset(desk.x - painter.width / 2, desk.y - painter.height / 2),
      );
      return;
    }

    if (scale < 0.18) return;

    // Keep first names whole instead of wrapping their final letters onto a
    // second line. The last initial gets its own line when names are shown.
    final displayLabel = visual.studentName != null && !useInitials
        ? label.replaceFirst(RegExp(r' (?=[^ ]+$)'), '\n')
        : label;
    var style = TextStyle(
      fontSize: desk.isSeat
          ? (useInitials ? 23 : (11 / scale).clamp(14, 18))
          : 16,
      fontWeight: desk.isSeat ? FontWeight.w600 : FontWeight.w400,
      color: desk.isSeat
          ? palette.deskText
          : palette.deskText.withValues(alpha: 0.7),
    );
    if (desk.isSeat) {
      final measured = textCache.get(displayLabel, style, 1000);
      if (measured.width > maxWidth) {
        style = style.copyWith(
          fontSize: style.fontSize! * maxWidth / measured.width,
        );
      }
    }
    final painter = textCache.get(displayLabel, style, maxWidth + 0.1);

    final hasDots = showTags && scale >= 0.8 && visual.tagColors.isNotEmpty;
    final dy = hasDots ? -5.0 : 0.0;
    painter.paint(
      canvas,
      Offset(desk.x - painter.width / 2, desk.y - painter.height / 2 + dy),
    );

    if (hasDots) {
      _paintTagDots(
        canvas,
        Offset(desk.x, desk.y + painter.height / 2 + dy + 5),
        visual.tagColors,
      );
    }
  }

  void _paintTagDots(Canvas canvas, Offset center, List<Color> colors) {
    const radius = 3.5;
    const spacing = 10.0;
    final total = (colors.length - 1) * spacing;
    for (var i = 0; i < colors.length; i++) {
      canvas.drawCircle(
        Offset(center.dx - total / 2 + i * spacing, center.dy),
        radius,
        Paint()..color = colors[i],
      );
    }
  }

  void _paintLockBadge(Canvas canvas, Desk desk) {
    final bounds = desk.bounds;
    canvas.drawCircle(
      Offset(bounds.right - 8, bounds.top + 8),
      6,
      Paint()..color = palette.wall.withValues(alpha: 0.75),
    );
  }

  void _paintPinBadge(Canvas canvas, Desk desk) {
    final bounds = desk.bounds;
    canvas
      ..drawCircle(
        Offset(bounds.left + 8, bounds.top + 8),
        6.5,
        Paint()..color = palette.selection,
      )
      ..drawCircle(
        Offset(bounds.left + 8, bounds.top + 8),
        2.5,
        Paint()..color = palette.floor,
      );
  }

  void _paintMarquee(Canvas canvas, Rect rect) {
    canvas
      ..drawRect(rect, Paint()..color = palette.marquee)
      ..drawRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 / scale
          ..color = palette.selection,
      );
  }

  void _paintRotationHandle(Canvas canvas, Offset center) {
    final radius = 9 / scale * 1.0;
    canvas
      ..drawCircle(center, radius, Paint()..color = palette.selection)
      ..drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 / scale
          ..color = palette.floor,
      );
  }

  Path _shapePath(Rect rect, DeskShape shape) => switch (shape) {
    DeskShape.rectangle => Path()..addRect(rect),
    DeskShape.rounded =>
      Path()..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8))),
    DeskShape.circle => Path()..addOval(rect),
    DeskShape.trapezoid =>
      Path()
        ..moveTo(rect.left + rect.width * 0.14, rect.top)
        ..lineTo(rect.right - rect.width * 0.14, rect.top)
        ..lineTo(rect.right, rect.bottom)
        ..lineTo(rect.left, rect.bottom)
        ..close(),
  };

  /// Dashes an arbitrary path, used for the "no student here yet" outline.
  void _drawDashedPath(
    Canvas canvas,
    Path path,
    Paint paint, {
    required double dash,
    required double gap,
  }) {
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(RoomPainter old) =>
      old.layout != layout ||
      old.visuals != visuals ||
      old.scale != scale ||
      old.pan != pan ||
      old.showGrid != showGrid ||
      old.showTags != showTags ||
      old.showNames != showNames ||
      old.showFacing != showFacing ||
      old.selectedGroupId != selectedGroupId ||
      old.marquee != marquee ||
      old.rotationHandle != rotationHandle ||
      old.palette.scheme != palette.scheme;
}
