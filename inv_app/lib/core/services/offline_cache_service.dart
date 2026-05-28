import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:inv_app/core/entities/offline_action.dart';

class OfflineCacheService {
  final SharedPreferences _sharedPreferences;
  static const String _keyActions = 'offline_actions';

  OfflineCacheService(this._sharedPreferences);

  Future<void> saveAction(OfflineAction action) async {
    final actions = await _getActionsList();
    actions.add(action);
    await _saveActionsList(actions);
  }

  Future<List<OfflineAction>> getUnsyncedActions() async {
    final actions = await _getActionsList();
    return actions.where((a) => !a.synced).toList();
  }

  Future<void> markAsSynced(String actionId) async {
    final actions = await _getActionsList();
    final updated = actions.map((a) {
      if (a.id == actionId) {
        return a.copyWith(synced: true);
      }
      return a;
    }).toList();
    await _saveActionsList(updated);
  }

  Future<void> clearSynced() async {
    final actions = await _getActionsList();
    final unsynced = actions.where((a) => !a.synced).toList();
    await _saveActionsList(unsynced);
  }

  Future<int> getUnsyncedCount() async {
    final unsynced = await getUnsyncedActions();
    return unsynced.length;
  }

  List<OfflineAction> _parseActions(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((e) => OfflineAction.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<OfflineAction>> _getActionsList() async {
    final raw = _sharedPreferences.getString(_keyActions);
    return _parseActions(raw);
  }

  Future<void> _saveActionsList(List<OfflineAction> actions) async {
    final encoded = jsonEncode(actions.map((a) => a.toJson()).toList());
    await _sharedPreferences.setString(_keyActions, encoded);
  }
}
