import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What a tapped notification asked the app to open.
class OpenAction {
  const OpenAction(this.open, this.alertId, this.vehicleId);

  /// "alerts", "message" (Message driver), "vehicle" (a payment) or "home".
  final String open;
  final String? alertId;
  final String? vehicleId;
}

/// Push notifications on Android (android/.../push/). The database sends them
/// through Firebase; this side only knows the phone's token and handles taps.
class PushService {
  static const _channel = MethodChannel('motor_track/push');

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// This phone's Firebase token, or null without Google Play services.
  static Future<String?> token() async {
    if (!supported) return null;
    try {
      return await _channel.invokeMethod<String>('token');
    } on PlatformException {
      return null;
    }
  }

  /// The notification the user tapped to open the app, once.
  static Future<OpenAction?> takeOpenAction() async {
    if (!supported) return null;
    final r = await _channel.invokeMapMethod<String, String?>('takeOpenAction');
    if (r == null || r['open'] == null) return null;
    String? id(String k) => (r[k] ?? '').isEmpty ? null : r[k];
    return OpenAction(r['open']!, id('alertId'), id('vehicleId'));
  }

  /// Called when a notification is tapped while the app is running.
  static void onOpened(VoidCallback callback) {
    if (!supported) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'opened') callback();
    });
  }
}
