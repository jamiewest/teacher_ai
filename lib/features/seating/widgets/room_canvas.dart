import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/responsive.dart';
import '../../../app/theme.dart';
import '../../../data/teacher_workspace.dart';
import '../../../domain/models/models.dart';
import '../room_view_controller.dart';
import '../seating_editor_controller.dart';
import '../seating_editor_state.dart';
import 'room_painter.dart';

/// What the in-flight gesture is doing.
enum _GestureMode { none, dragDesk, marquee, panZoom, rotate }

/// The interactive classroom.
///
/// All pointer math converts screen points into room centimeters through
/// [RoomViewController] before touching the model, so a desk lands where the
/// teacher dropped it at any zoom level or window size.
class RoomCanvas extends StatefulWidget {
  const RoomCanvas({
    required this.controller,
    required this.view,
    required this.workspace,
    this.onSeatTapped,
    this.onDeskMenu,
    super.key,
  });

  final SeatingEditorController controller;
  final RoomViewController view;
  final TeacherWorkspace workspace;

  /// Fired when an already-selected seat is tapped again — the "act on this
  /// seat" gesture, used instead of a double tap so it works on touch.
  final void Function(Desk desk)? onSeatTapped;

  /// Fired on right-click or long-press.
  final void Function(Desk desk, Offset globalPosition)? onDeskMenu;

  @override
  State<RoomCanvas> createState() => _RoomCanvasState();
}

class _RoomCanvasState extends State<RoomCanvas> {
  final _textCache = TextLayoutCache();
  final _focusNode = FocusNode(debugLabel: 'RoomCanvas');

  _GestureMode _mode = _GestureMode.none;
  String? _dragAnchorId;
  Offset? _marqueeStart;
  Rect? _marquee;
  double _gestureStartScale = 1;
  Offset _gestureStartRoomFocal = Offset.zero;
  bool _additiveMarquee = false;

  /// Where the finger or cursor actually went down.
  ///
  /// `onScaleStart` reports its focal point only after the touch slop has been
  /// consumed, which is far enough at low zoom to fall outside a small desk.
  /// Hit-testing against the real press point is what makes grabbing a desk
  /// reliable.
  Offset? _pointerDownLocal;

  /// Room-space offset from the pressed point to the dragged desk's center,
  /// so a desk grabbed by its edge does not jump under the cursor.
  Offset _dragGrabOffset = Offset.zero;

  /// How close a tap has to be, in screen pixels, to grab the rotation handle.
  static const double _handleHitRadius = 20;

  /// Extra hit slop around desks, in screen pixels. Fingers are imprecise.
  double get _hitSlopPixels => context.isTouch ? 8 : 2;

  @override
  void dispose() {
    _textCache.clear();
    _focusNode.dispose();
    super.dispose();
  }

  SeatingEditorController get _editor => widget.controller;
  RoomViewController get _view => widget.view;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        // Deferred so the first fit does not notify during build.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _view.setViewport(size, _editor.layout.roomSize);
        });

        return Focus(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: _onKeyEvent,
          child: Listener(
            onPointerDown: (event) => _pointerDownLocal = event.localPosition,
            onPointerSignal: _onPointerSignal,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: _onTapUp,
              onSecondaryTapUp: _onSecondaryTapUp,
              onLongPressStart: _onLongPressStart,
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              onScaleEnd: _onScaleEnd,
              // Rebuilt together so the cursor tracks the active tool and
              // the painting tracks both the model and the viewport.
              child: ListenableBuilder(
                listenable: Listenable.merge([_editor, _view]),
                builder: (context, _) => MouseRegion(
                  cursor: _cursorForTool(),
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: RoomPainter(
                      layout: _editor.layout,
                      visuals: _buildVisuals(),
                      palette: RoomPalette(Theme.of(context).colorScheme),
                      textCache: _textCache,
                      scale: _view.scale,
                      pan: _view.pan,
                      showGrid:
                          _editor.mode == EditorMode.design && _editor.showGrid,
                      showTags: _editor.showTags,
                      showFacing: _editor.mode == EditorMode.design,
                      marquee: _marquee,
                      rotationHandle: _rotationHandlePosition(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  MouseCursor _cursorForTool() => switch (_editor.tool) {
    EditorTool.pan => SystemMouseCursors.grab,
    EditorTool.addDesk => SystemMouseCursors.precise,
    EditorTool.select => SystemMouseCursors.basic,
  };

  /// Resolves model + roster into the flat records the painter draws.
  List<DeskVisual> _buildVisuals() {
    final layout = _editor.layout;
    final tags = widget.workspace.tagsById;
    return [
      for (final desk in layout.desks)
        () {
          final group = desk.groupId == null
              ? null
              : layout.groupById(desk.groupId!);
          final student = _editor.studentAt(desk.id);
          return DeskVisual(
            desk: desk,
            studentName: student?.shortName,
            studentInitials: student?.initials,
            // Three dots is all that fits on a desk before it turns to noise.
            tagColors: student == null
                ? const <Color>[]
                : [
                    for (final id in student.tagIds.take(3))
                      if (tags[id] != null) Color(tags[id]!.colorValue),
                  ],
            groupColor: group == null ? null : Color(group.colorValue),
            groupName: group?.name,
            isSelected: _editor.selection.contains(desk.id),
            isPinned: _editor.isPinned(desk.id),
          );
        }(),
    ];
  }

  /// Room-space position of the rotation handle for a single selected desk.
  ///
  /// The handle sits off the desk's leading edge and travels with its
  /// rotation, so it always reads as "the direction this desk faces".
  Offset? _rotationHandlePosition() {
    final desk = _editor.soleSelection;
    if (_editor.mode != EditorMode.design) return null;
    if (desk == null || desk.locked) return null;
    final distance = desk.height / 2 + _view.screenToRoomDistance(28);
    final radians = desk.rotation * math.pi / 180.0;
    return Offset(
      desk.x + distance * math.sin(radians),
      desk.y - distance * math.cos(radians),
    );
  }

  // --- Pointer -------------------------------------------------------------

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    // Trackpads and wheels both arrive here; a modest exponent keeps the zoom
    // from overshooting on a flick.
    final factor = math.exp(-event.scrollDelta.dy / 320);
    _view.zoomBy(factor, event.localPosition);
  }

  void _onTapUp(TapUpDetails details) {
    _focusNode.requestFocus();
    final roomPoint = _view.toRoom(details.localPosition);

    if (_editor.tool == EditorTool.addDesk) {
      _editor.addDesk(roomPoint);
      return;
    }

    final desk = _editor.deskAt(
      roomPoint,
      padding: _view.screenToRoomDistance(_hitSlopPixels),
    );

    if (desk == null) {
      _editor.clearSelection();
      return;
    }

    if (_editor.mode == EditorMode.seating) {
      if (!desk.isSeat) return;
      _editor.selectOnly(desk.id);
      final studentId = _editor.pendingStudentId;
      if (studentId != null) {
        _editor.placeStudent(desk.id, studentId);
      } else {
        widget.onSeatTapped?.call(desk);
      }
      return;
    }

    if (HardwareKeyboard.instance.isShiftPressed) {
      _editor.toggleSelection(desk.id);
      return;
    }

    // Tapping an already-selected seat acts on it. A second tap is reachable
    // on touch, where a double tap fights the pinch recognizer.
    final wasSoleSelection = _editor.soleSelection?.id == desk.id;
    _editor.selectOnly(desk.id);
    if (wasSoleSelection && desk.isSeat) {
      widget.onSeatTapped?.call(desk);
    }
  }

  void _onSecondaryTapUp(TapUpDetails details) =>
      _openMenuAt(details.localPosition, details.globalPosition);

  void _onLongPressStart(LongPressStartDetails details) =>
      _openMenuAt(details.localPosition, details.globalPosition);

  void _openMenuAt(Offset localPosition, Offset globalPosition) {
    final desk = _editor.deskAt(
      _view.toRoom(localPosition),
      padding: _view.screenToRoomDistance(_hitSlopPixels),
    );
    if (desk == null) return;
    if (!_editor.selection.contains(desk.id)) _editor.selectOnly(desk.id);
    widget.onDeskMenu?.call(desk, globalPosition);
  }

  // --- Drag / pinch --------------------------------------------------------

  void _onScaleStart(ScaleStartDetails details) {
    _focusNode.requestFocus();
    _gestureStartScale = _view.scale;
    _gestureStartRoomFocal = _view.toRoom(details.localFocalPoint);

    if (_editor.mode == EditorMode.seating ||
        details.pointerCount > 1 ||
        _editor.tool == EditorTool.pan) {
      _mode = _GestureMode.panZoom;
      return;
    }

    // Hit-test where the pointer went down, not where the gesture was
    // recognized, so slop cannot slide the test off a small desk.
    final roomPoint = _view.toRoom(
      _pointerDownLocal ?? details.localFocalPoint,
    );

    // The rotation handle wins over the desk beneath it.
    final handle = _rotationHandlePosition();
    if (handle != null &&
        (roomPoint - handle).distance <=
            _view.screenToRoomDistance(_handleHitRadius)) {
      _mode = _GestureMode.rotate;
      _editor.beginInteraction();
      return;
    }

    final desk = _editor.deskAt(
      roomPoint,
      padding: _view.screenToRoomDistance(_hitSlopPixels),
    );

    if (desk != null && !desk.locked) {
      // Dragging a desk that is not in the selection selects it first, so a
      // drag never silently moves something the teacher cannot see.
      if (!_editor.selection.contains(desk.id)) _editor.selectOnly(desk.id);
      _mode = _GestureMode.dragDesk;
      _dragAnchorId = desk.id;
      _dragGrabOffset = desk.center - roomPoint;
      _editor.beginInteraction();
      return;
    }

    if (_editor.tool == EditorTool.select) {
      _mode = _GestureMode.marquee;
      _marqueeStart = roomPoint;
      _additiveMarquee = HardwareKeyboard.instance.isShiftPressed;
      return;
    }

    _mode = _GestureMode.panZoom;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    // A second finger always means navigate, whatever was happening before.
    if (details.pointerCount > 1 && _mode != _GestureMode.panZoom) {
      _finishInteraction();
      _mode = _GestureMode.panZoom;
      _gestureStartScale = _view.scale;
      _gestureStartRoomFocal = _view.toRoom(details.localFocalPoint);
      return;
    }

    switch (_mode) {
      case _GestureMode.panZoom:
        final scale = _gestureStartScale * details.scale;
        _view.setTransform(
          scale: scale,
          // Keep the point under the fingers fixed as the scale changes.
          pan:
              details.localFocalPoint -
              _gestureStartRoomFocal *
                  scale.clamp(
                    RoomViewController.minScale,
                    RoomViewController.maxScale,
                  ),
        );

      case _GestureMode.dragDesk:
        final anchor = _dragAnchorId;
        if (anchor == null) return;
        _editor.dragSelectionTo(
          anchor,
          _view.toRoom(details.localFocalPoint) + _dragGrabOffset,
        );

      case _GestureMode.marquee:
        final start = _marqueeStart;
        if (start == null) return;
        setState(() {
          _marquee = Rect.fromPoints(
            start,
            _view.toRoom(details.localFocalPoint),
          );
        });

      case _GestureMode.rotate:
        final desk = _editor.soleSelection;
        if (desk == null) return;
        final point = _view.toRoom(details.localFocalPoint);
        final vector = point - desk.center;
        // Handle sits "above" the desk at 0 degrees, hence the quarter turn.
        final degrees = math.atan2(vector.dy, vector.dx) * 180 / math.pi + 90;
        _editor.setDeskRotation(desk.id, degrees);

      case _GestureMode.none:
        break;
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_mode == _GestureMode.marquee && _marquee != null) {
      _editor.selectInRect(_marquee!, additive: _additiveMarquee);
    }
    _finishInteraction();
    _mode = _GestureMode.none;
  }

  void _finishInteraction() {
    if (_mode == _GestureMode.dragDesk || _mode == _GestureMode.rotate) {
      _editor.endInteraction();
    }
    _dragAnchorId = null;
    _dragGrabOffset = Offset.zero;
    _marqueeStart = null;
    if (_marquee != null) setState(() => _marquee = null);
  }

  // --- Keyboard ------------------------------------------------------------

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keys = HardwareKeyboard.instance;
    final meta = keys.isControlPressed || keys.isMetaPressed;

    if (_editor.mode == EditorMode.seating) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.escape:
          _editor.pickStudent(null);
          _editor.clearSelection();
        case LogicalKeyboardKey.delete:
        case LogicalKeyboardKey.backspace:
          for (final id in _editor.selection.toList()) {
            _editor.clearSeat(id);
          }
        case LogicalKeyboardKey.keyZ when meta && keys.isShiftPressed:
          _editor.redo();
        case LogicalKeyboardKey.keyZ when meta:
          _editor.undo();
        case LogicalKeyboardKey.keyY when meta:
          _editor.redo();
        case LogicalKeyboardKey.equal when meta:
          _view.zoomAtCenter(1.2);
        case LogicalKeyboardKey.minus when meta:
          _view.zoomAtCenter(1 / 1.2);
        case LogicalKeyboardKey.digit0 when meta:
          _view.fit(_editor.layout.roomSize);
        default:
          return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        _editor.nudgeSelection(const Offset(-1, 0));
      case LogicalKeyboardKey.arrowRight:
        _editor.nudgeSelection(const Offset(1, 0));
      case LogicalKeyboardKey.arrowUp:
        _editor.nudgeSelection(const Offset(0, -1));
      case LogicalKeyboardKey.arrowDown:
        _editor.nudgeSelection(const Offset(0, 1));
      case LogicalKeyboardKey.delete:
      case LogicalKeyboardKey.backspace:
        _editor.deleteSelection();
      case LogicalKeyboardKey.escape:
        _editor.clearSelection();
      case LogicalKeyboardKey.keyA when meta:
        _editor.selectAllSeats();
      case LogicalKeyboardKey.keyD when meta:
        _editor.duplicateSelection();
      case LogicalKeyboardKey.keyG when meta:
        _editor.groupSelection();
      case LogicalKeyboardKey.keyZ when meta && keys.isShiftPressed:
        _editor.redo();
      case LogicalKeyboardKey.keyZ when meta:
        _editor.undo();
      case LogicalKeyboardKey.keyY when meta:
        _editor.redo();
      case LogicalKeyboardKey.equal when meta:
        _view.zoomAtCenter(1.2);
      case LogicalKeyboardKey.minus when meta:
        _view.zoomAtCenter(1 / 1.2);
      case LogicalKeyboardKey.digit0 when meta:
        _view.fit(_editor.layout.roomSize);
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }
}
