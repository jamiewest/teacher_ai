import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Owns the canvas viewport: how many screen pixels one room centimeter takes,
/// and where the room's origin sits on screen.
///
/// Keeping this separate from the editor means panning and zooming never touch
/// the undo history, and toolbar buttons (zoom in, fit) can drive the view
/// without reaching into the canvas widget.
class RoomViewController extends ChangeNotifier {
  /// Screen pixels per room centimeter.
  double _scale = 1;

  /// Screen-space position of the room's top-left corner.
  Offset _pan = Offset.zero;

  Size _viewport = Size.zero;
  bool _fitToViewport = true;

  /// Below this the room is a smudge; above it desks are absurdly large.
  static const double minScale = 0.06;
  static const double maxScale = 4.0;

  double get scale => _scale;
  Offset get pan => _pan;
  Size get viewport => _viewport;

  /// Zoom as a percentage, for the toolbar readout.
  int get zoomPercent => (_scale * 100).round();

  Offset toRoom(Offset screenPoint) => (screenPoint - _pan) / _scale;

  Offset toScreen(Offset roomPoint) => roomPoint * _scale + _pan;

  /// Converts a screen-space distance to room centimeters, for hit-test
  /// padding that should stay a constant finger size on screen.
  double screenToRoomDistance(double pixels) => pixels / _scale;

  void setViewport(Size size, Size roomSize) {
    if (_viewport == size) return;
    final previous = _viewport;
    _viewport = size;
    if (size.isEmpty) return;
    if (_fitToViewport) {
      fit(roomSize);
    } else {
      _pan += Offset(
        (size.width - previous.width) / 2,
        (size.height - previous.height) / 2,
      );
      notifyListeners();
    }
  }

  /// Scales and centers the room so all of it is visible.
  void fit(Size roomSize, {double padding = 32, bool notify = true}) {
    if (_viewport.isEmpty || roomSize.isEmpty) return;
    _fitToViewport = true;
    final available = Size(
      math.max(1, _viewport.width - padding * 2),
      math.max(1, _viewport.height - padding * 2),
    );
    final next = math
        .min(
          available.width / roomSize.width,
          available.height / roomSize.height,
        )
        .clamp(minScale, maxScale);

    _scale = next;
    _pan = Offset(
      (_viewport.width - roomSize.width * next) / 2,
      (_viewport.height - roomSize.height * next) / 2,
    );
    if (notify) notifyListeners();
  }

  /// Zooms by [factor] while keeping [focalScreen] pinned to the same spot in
  /// the room, which is what makes wheel and pinch zoom feel anchored.
  void zoomBy(double factor, Offset focalScreen) {
    final next = (_scale * factor).clamp(minScale, maxScale);
    if (next == _scale) return;
    _fitToViewport = false;
    final roomPoint = toRoom(focalScreen);
    _scale = next;
    _pan = focalScreen - roomPoint * _scale;
    notifyListeners();
  }

  /// Zooms around the middle of the viewport, for keyboard and toolbar zoom.
  void zoomAtCenter(double factor) =>
      zoomBy(factor, Offset(_viewport.width / 2, _viewport.height / 2));

  void panBy(Offset delta) {
    if (delta == Offset.zero) return;
    _fitToViewport = false;
    _pan += delta;
    notifyListeners();
  }

  /// Applies an absolute transform, used while a pinch gesture is in flight.
  void setTransform({required double scale, required Offset pan}) {
    final clamped = scale.clamp(minScale, maxScale);
    if (clamped == _scale && pan == _pan) return;
    _fitToViewport = false;
    _scale = clamped;
    _pan = pan;
    notifyListeners();
  }

  /// Centers the view on a room point without changing zoom.
  void centerOn(Offset roomPoint) {
    _fitToViewport = false;
    _pan =
        Offset(_viewport.width / 2, _viewport.height / 2) - roomPoint * _scale;
    notifyListeners();
  }
}
