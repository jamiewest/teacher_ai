import 'package:flutter/material.dart';

/// Compact grid/wrap of circular color swatches with crisp selection feedback.
class ColorSwatchGrid extends StatelessWidget {
  const ColorSwatchGrid({
    required this.colors,
    required this.selectedColorValue,
    required this.onSelected,
    this.radius = 14,
    this.spacing = 8,
    super.key,
  });

  final List<int> colors;
  final int selectedColorValue;
  final ValueChanged<int> onSelected;
  final double radius;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: spacing,
      runSpacing: spacing,
      children: [
        for (final value in colors)
          () {
            final color = Color(value);
            final selected = value == selectedColorValue;
            final checkColor =
                ThemeData.estimateBrightnessForColor(color) == Brightness.dark
                ? Colors.white
                : Colors.black;
            return Semantics(
              button: true,
              selected: selected,
              label: 'Color swatch',
              child: InkWell(
                borderRadius: BorderRadius.circular(radius + 4),
                onTap: () => onSelected(value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? scheme.onSurface : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: CircleAvatar(
                    backgroundColor: color,
                    radius: radius,
                    child: selected
                        ? Icon(Icons.check, size: radius + 2, color: checkColor)
                        : null,
                  ),
                ),
              ),
            );
          }(),
      ],
    );
  }
}
