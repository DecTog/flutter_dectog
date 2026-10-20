import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../services/platform_version.dart';

/// Label layout of the native paste control.
enum DectogPasteDisplayMode { iconAndLabel, iconOnly, labelOnly }

/// Corner style of the native paste control.
enum DectogPasteCornerStyle { capsule, dynamic, fixed, large, medium, small }

/// A native `UIPasteControl` (iOS 16+) wired to DecTog — Branch's
/// `BranchPasteControl`. Tapping it reads the pasteboard WITHOUT the
/// system "Allow paste" alert (the tap is the user's consent); when the
/// pasteboard holds a DecTog link the SDK sends it as a deterministic
/// late claim (`claim_source: paste_control`) and the upgraded verdict is
/// emitted on `FlutterDectog().onAppInstalled`.
///
/// Use it as a recovery path on your onboarding / "I have an invite link"
/// screen for users who declined the automatic read, or for apps that opt
/// out of the automatic read (`DectogCollection.pasteboard`). The control fills the frame you give
/// it; Apple decides its label ("Paste") and tint rules. It renders nothing
/// on Android, desktop, web and iOS < 16.
class DectogPasteButton extends StatelessWidget {
  const DectogPasteButton({
    super.key,
    this.size = const Size(200, 44),
    this.displayMode = DectogPasteDisplayMode.iconAndLabel,
    this.cornerStyle = DectogPasteCornerStyle.capsule,
    this.backgroundColor,
    this.foregroundColor,
  });

  /// Platform view type registered by the iOS plugin.
  static const String viewType = 'dectog_paste_control';

  /// Frame of the native control.
  final Size size;
  final DectogPasteDisplayMode displayMode;
  final DectogPasteCornerStyle cornerStyle;

  /// Optional tint colours (passed as 0xAARRGGBB).
  final Color? backgroundColor;
  final Color? foregroundColor;

  /// Tests: force the supported/unsupported decision.
  @visibleForTesting
  static bool Function()? debugIsSupportedOverride;

  /// Whether the native control exists on this device (iOS 16+).
  static bool get isSupported {
    final override = debugIsSupportedOverride;
    if (override != null) return override();
    if (kIsWeb) return false;
    return Platform.isIOS &&
        iosMajorVersion(Platform.operatingSystemVersion) >= 16;
  }

  @override
  Widget build(BuildContext context) {
    if (!isSupported) return const SizedBox.shrink();
    return SizedBox(
      width: size.width,
      height: size.height,
      child: UiKitView(
        viewType: viewType,
        creationParams: <String, Object?>{
          'displayMode': displayMode.name,
          'cornerStyle': cornerStyle.name,
          if (backgroundColor != null)
            'backgroundColor': backgroundColor!.toARGB32(),
          if (foregroundColor != null)
            'foregroundColor': foregroundColor!.toARGB32(),
        },
        creationParamsCodec: const StandardMessageCodec(),
      ),
    );
  }
}
