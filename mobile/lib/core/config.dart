import 'package:shared_preferences/shared_preferences.dart';

class AppConfig {
  // Production worker URL — update this before building for release
  static const String defaultWorkerUrl =
      'wss://doctransit.in';

  // Dev fallbacks
  static const String androidEmulatorUrl = 'ws://10.0.2.2:8787';
  static const String iosSimulatorUrl = 'ws://localhost:8787';

  static Future<String> getWorkerUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('worker_url') ?? defaultWorkerUrl;
    } catch (_) {
      return defaultWorkerUrl;
    }
  }

  static Future<void> saveWorkerUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('worker_url', url);
  }

  // Sync getter for compile-time contexts — use getWorkerUrl() when possible
  static String get workerWsUrl => defaultWorkerUrl;
}
