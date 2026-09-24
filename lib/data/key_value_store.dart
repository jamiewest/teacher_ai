import 'package:shared_preferences/shared_preferences.dart';

/// Minimal persistence surface the repository needs.
///
/// Keeping this behind an interface means the workspace can be tested without
/// a platform channel, and the browser's localStorage can be swapped for a
/// server or a file later without touching the domain.
abstract interface class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
}

/// Backed by `shared_preferences`, which is localStorage on the web.
class SharedPreferencesStore implements KeyValueStore {
  SharedPreferencesStore();

  SharedPreferences? _prefs;

  Future<SharedPreferences> _instance() async =>
      _prefs ??= await SharedPreferences.getInstance();

  @override
  Future<String?> read(String key) async => (await _instance()).getString(key);

  @override
  Future<void> write(String key, String value) async =>
      (await _instance()).setString(key, value);

  @override
  Future<void> remove(String key) async => (await _instance()).remove(key);
}

/// In-memory store used by tests and by the "try it without saving" path.
class InMemoryStore implements KeyValueStore {
  final _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> remove(String key) async => _values.remove(key);
}
