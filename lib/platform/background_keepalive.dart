import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_background/flutter_background.dart';

/// Keeps the app process — and therefore the UDP socket and the auto-mix
/// timers — running while the phone is locked or the musician switches to
/// another app (a chord-sheet app, for example) during a service.
///
/// On Android this runs a foreground service with a persistent notification.
/// On every other platform each method is a safe no-op, so callers don't need
/// to branch on the platform. iOS has no equivalent (the OS suspends the app);
/// there the app must stay in the foreground with the screen awake.
class BackgroundKeepAlive {
  BackgroundKeepAlive._();

  static bool _initialized = false;

  static Future<bool> _ensureInitialized() async {
    if (!Platform.isAndroid) return false;
    if (_initialized) return true;
    try {
      // Not marked const so we don't depend on the plugin's constructors being
      // const across versions.
      final config = FlutterBackgroundAndroidConfig(
        notificationTitle: 'mxstage conectado',
        notificationText: 'Mantendo o balanço do seu retorno em segundo plano.',
        notificationImportance: AndroidNotificationImportance.normal,
        notificationIcon:
            const AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
        // Hold a Wi-Fi lock so the radio doesn't doze and drop OSC packets.
        enableWifiLock: true,
      );
      // Prompts for the ignore-battery-optimizations permission the first time.
      _initialized = await FlutterBackground.initialize(androidConfig: config);
    } catch (e) {
      debugPrint('BackgroundKeepAlive: initialize failed: $e');
      _initialized = false;
    }
    return _initialized;
  }

  /// Start the foreground service. Safe to call repeatedly; only starts if not
  /// already running. Silently no-ops if the platform is unsupported or the
  /// user denied the required permission.
  static Future<void> enable() async {
    if (!await _ensureInitialized()) return;
    try {
      if (!FlutterBackground.isBackgroundExecutionEnabled) {
        await FlutterBackground.enableBackgroundExecution();
      }
    } catch (e) {
      debugPrint('BackgroundKeepAlive: enable failed: $e');
    }
  }

  /// Stop the foreground service. Safe to call when it was never started.
  static Future<void> disable() async {
    if (!Platform.isAndroid || !_initialized) return;
    try {
      if (FlutterBackground.isBackgroundExecutionEnabled) {
        await FlutterBackground.disableBackgroundExecution();
      }
    } catch (e) {
      debugPrint('BackgroundKeepAlive: disable failed: $e');
    }
  }
}
