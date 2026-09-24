import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Width bands the layout responds to.
///
/// The seating editor is the reason these exist: on a phone the canvas needs
/// the whole window and the panels become sheets, while on a desktop the
/// roster and inspector can sit beside it permanently.
enum FormFactor {
  /// Phone, or a narrow browser window. One thing at a time.
  compact,

  /// Tablet or split-screen. Canvas plus one docked panel.
  medium,

  /// Desktop. Canvas plus roster and inspector at once.
  expanded;

  bool get isCompact => this == FormFactor.compact;
  bool get isMedium => this == FormFactor.medium;
  bool get isExpanded => this == FormFactor.expanded;

  /// True when there is room to dock a panel beside the canvas.
  bool get canDockPanels => this != FormFactor.compact;
}

/// Whether the user is driving with a precise pointer or a finger.
///
/// This is a separate axis from width: modifier keys and hover affordances do
/// not exist on touch, so anything they gate needs a visible control too.
enum InputMode { pointer, touch }

class Breakpoints {
  const Breakpoints._();

  static const double compact = 700;
  static const double medium = 1150;

  static FormFactor formFactorFor(double width) {
    if (width < compact) return FormFactor.compact;
    if (width < medium) return FormFactor.medium;
    return FormFactor.expanded;
  }
}

extension ResponsiveContext on BuildContext {
  /// Form factor derived from the current window width.
  FormFactor get formFactor =>
      Breakpoints.formFactorFor(MediaQuery.sizeOf(this).width);

  bool get isCompact => formFactor.isCompact;
  bool get isExpanded => formFactor.isExpanded;

  /// Best guess at the primary input device.
  ///
  /// Touch platforms get larger hit targets and an always-visible tool
  /// switcher, because they have no modifier keys to fall back on.
  InputMode get inputMode => switch (defaultTargetPlatform) {
    TargetPlatform.iOS || TargetPlatform.android => InputMode.touch,
    _ => InputMode.pointer,
  };

  bool get isTouch => inputMode == InputMode.touch;
}
