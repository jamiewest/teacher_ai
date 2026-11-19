import 'package:flutter/material.dart';

import '../room_view_controller.dart';

/// Sleek translucent Material 3 pill surface used for canvas-floating controls.
class FloatingPillSurface extends StatelessWidget {
  const FloatingPillSurface({
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.color,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: color ?? scheme.surfaceContainerHigh.withValues(alpha: 0.94),
      elevation: 2,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius,
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// Shared floating zoom and fullscreen control pill for both Live and Edit modes.
class CanvasZoomPill extends StatelessWidget {
  const CanvasZoomPill({
    required this.view,
    required this.roomSize,
    required this.expanded,
    required this.onToggleExpanded,
    this.compact = false,
    super.key,
  });

  final RoomViewController view;
  final Size roomSize;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final buttonStyle = compact
        ? IconButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            minimumSize: const Size(34, 34),
            fixedSize: const Size(34, 34),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          )
        : IconButton.styleFrom(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          );
    final iconSize = compact ? 18.0 : 20.0;

    return ListenableBuilder(
      listenable: view,
      builder: (context, _) => FloatingPillSurface(
        padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 6, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              style: buttonStyle,
              tooltip: 'Zoom out',
              onPressed: () => view.zoomAtCenter(1 / 1.25),
              icon: Icon(Icons.remove, size: iconSize),
            ),
            if (!compact)
              Tooltip(
                message: 'Reset zoom',
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => view.fit(roomSize),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    child: Text(
                      '${view.zoomPercent}%',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                ),
              ),
            IconButton(
              style: buttonStyle,
              tooltip: 'Zoom in',
              onPressed: () => view.zoomAtCenter(1.25),
              icon: Icon(Icons.add, size: iconSize),
            ),
            IconButton(
              style: buttonStyle,
              tooltip: 'Fit room',
              onPressed: () => view.fit(roomSize),
              icon: Icon(Icons.fit_screen_outlined, size: iconSize),
            ),
            const SizedBox(height: 18, child: VerticalDivider(width: 8)),
            IconButton(
              style: buttonStyle,
              tooltip: expanded ? 'Restore view' : 'Expand view',
              onPressed: onToggleExpanded,
              icon: Icon(
                expanded ? Icons.fullscreen_exit : Icons.fullscreen,
                size: iconSize,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
