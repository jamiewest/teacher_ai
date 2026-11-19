import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/ops/layout_presets.dart';
import '../features/seating/widgets/room_painter.dart';
import 'theme.dart';

class ClassroomSignIn extends StatelessWidget {
  const ClassroomSignIn({
    required this.onSignIn,
    this.message,
    this.onRemoveCopy,
    super.key,
  });

  final VoidCallback onSignIn;
  final String? message;
  final VoidCallback? onRemoveCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
      backgroundColor: colors.surfaceContainerLow,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 640;
                  final content = Padding(
                    padding: EdgeInsets.all(wide ? 36 : 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.school_outlined, color: colors.primary),
                            const SizedBox(width: 10),
                            Text(
                              'Teacher AI',
                              style: theme.textTheme.titleMedium,
                            ),
                          ],
                        ),
                        const SizedBox(height: 28),
                        Semantics(
                          header: true,
                          child: Text(
                            'Your classroom',
                            style: theme.textTheme.headlineMedium,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Sign in to open your seating charts, roster, and schedule.',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        if (message != null) ...[
                          const SizedBox(height: 16),
                          Semantics(liveRegion: true, child: Text(message!)),
                        ],
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: onSignIn,
                          icon: const Icon(Icons.arrow_forward, size: 18),
                          iconAlignment: IconAlignment.end,
                          label: const Text('Sign in'),
                        ),
                        if (onRemoveCopy != null)
                          TextButton(
                            onPressed: onRemoveCopy,
                            child: const Text('Remove device copy'),
                          ),
                      ],
                    ),
                  );
                  return Card.outlined(
                    margin: EdgeInsets.zero,
                    color: colors.surface,
                    clipBehavior: Clip.antiAlias,
                    child: wide
                        ? Row(
                            children: [
                              const Expanded(
                                child: SizedBox(
                                  height: 350,
                                  child: _SeatingPreview(),
                                ),
                              ),
                              Expanded(child: content),
                            ],
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(
                                height: 172,
                                child: _SeatingPreview(),
                              ),
                              content,
                            ],
                          ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Use the editor's own preset and painter so the preview follows the room theme.
class _SeatingPreview extends StatelessWidget {
  const _SeatingPreview();

  static final layout = buildPresetLayout(preset: 'pods', name: 'Classroom');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: ColoredBox(
        color: scheme.secondaryContainer.withValues(alpha: 0.65),
        child: LayoutBuilder(
          builder: (context, size) {
            final scale = math.min(
              size.maxWidth * .82 / layout.roomWidth,
              size.maxHeight * .81 / layout.roomHeight,
            );
            return CustomPaint(
              painter: RoomPainter(
                layout: layout,
                visuals: [
                  for (final (index, desk) in layout.desks.indexed)
                    DeskVisual(
                      desk: desk,
                      studentName: desk.isSeat ? '${index + 1}' : null,
                      groupColor: desk.groupId == null
                          ? null
                          : Color(layout.groupById(desk.groupId!)!.colorValue),
                    ),
                ],
                palette: RoomPalette.of(context),
                textCache: TextLayoutCache(),
                scale: scale,
                pan: Offset(
                  (size.maxWidth - scale * layout.roomWidth) / 2,
                  (size.maxHeight - scale * layout.roomHeight) / 2,
                ),
                showNames: scale > .28,
                showFacing: false,
              ),
              size: size.biggest,
            );
          },
        ),
      ),
    );
  }
}
