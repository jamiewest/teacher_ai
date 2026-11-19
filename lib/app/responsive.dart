import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Width bands the layout responds to.
///
/// On compact widths the classroom canvas takes the full window and secondary
/// panels open as sheets; on expanded widths the roster, inspector, or live
/// controls dock beside the canvas.
enum FormFactor {
  /// Phone, or a narrow browser window. One primary view at a time.
  compact,

  /// Tablet or split-screen. Canvas plus top bar and adaptive sheets.
  medium,

  /// Desktop or landscape tablet. Canvas plus docked side panel.
  expanded;

  bool get isCompact => this == FormFactor.compact;
  bool get isMedium => this == FormFactor.medium;
  bool get isExpanded => this == FormFactor.expanded;

  /// True when there is room to dock a panel beside the canvas.
  bool get canDockPanels => this == FormFactor.expanded;
}

/// Whether the user is driving with a precise pointer or a finger.
///
/// This is a separate axis from width: modifier keys and hover affordances do
/// not exist on touch, so anything they gate needs a visible control too.
enum InputMode { pointer, touch }

class Breakpoints {
  const Breakpoints._();

  static const double compact = 600;
  static const double medium = 960;

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

  /// True for short landscape phone viewports where vertical space is scarce.
  bool get isShortViewport => MediaQuery.sizeOf(this).height < 520;

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
