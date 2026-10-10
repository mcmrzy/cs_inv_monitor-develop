import 'package:dio/dio.dart';
import 'package:inv_app/core/errors/failures.dart';
import 'package:inv_app/core/services/storage_service.dart';
import 'package:inv_app/core/utils/api_response.dart';
import 'package:inv_app/features/station/domain/repositories/station_repository.dart';

class OwnedDevicePage {
  final List<Map<String, dynamic>> items;
  final bool hasMore;

  const OwnedDevicePage(this.items, {required this.hasMore});
}

enum OwnedDeviceAssociation { added, alreadyAssigned }

class OwnedDeviceSelectionService {
  final Dio dio;
  final StorageService storage;
  final StationRepository stations;

  const OwnedDeviceSelectionService({
    required this.dio,
    required this.storage,
    required this.stations,
  });

  bool _ownedBy(Map device, int userId) {
    final owner = device.containsKey('owner_user_id')
        ? device['owner_user_id']
        : device['user_id'];
    return owner == userId;
  }

  Future<int> _userId() async {
    final id = await storage.getUserId();
    if (id == null || id <= 0) {
      throw const UnauthorizedFailure('Login required');
    }
    return id;
  }

  Future<OwnedDevicePage> load({int page = 1, String keyword = ''}) async {
    final userId = await _userId();
    const pageSize = 20;
    // Use the authenticated device list, including its existing server search.
    final response = await dio.get(
      '/devices',
      queryParameters: {
        'page': page,
        'page_size': pageSize,
        if (keyword.trim().isNotEmpty) 'keyword': keyword.trim(),
      },
    );
    final data = unwrapApiResponse<Map<String, dynamic>>(
      response.data,
      validate: (value) => value is Map<String, dynamic>,
      expected: 'a device page',
    );
    final items = data['items'];
    final total = data['total'];
    if (items is! List || total is! int || total < 0) {
      throw const FormatException('Invalid device page');
    }
    if (await _userId() != userId) {
      throw const UnauthorizedFailure('Account changed');
    }
    return OwnedDevicePage(
      items.whereType<Map<String, dynamic>>().where((device) {
        // Shared and admin-visible devices are not this account's devices.
        return _ownedBy(device, userId) &&
            device['sn'] is String &&
            (device['sn'] as String).isNotEmpty;
      }).toList(),
      hasMore: page * pageSize < total && items.isNotEmpty,
    );
  }

  Future<OwnedDeviceAssociation> associate(String sn, int stationId) async {
    final userId = await _userId();
    if (stationId <= 0) {
      throw const ValidationFailure('Select a station');
    }
    final response = await dio.get('/devices/by-sn/${Uri.encodeComponent(sn)}');
    final data = unwrapApiResponse<Map<String, dynamic>>(
      response.data,
      validate: (value) => value is Map<String, dynamic>,
      expected: 'device detail',
    );
    final device = data['device'];
    if (device is! Map || device['sn'] != sn || !_ownedBy(device, userId)) {
      throw const ForbiddenFailure('Device is not owned by you');
    }
    if (!device.containsKey('station_id')) {
      throw const FormatException(
        'Device detail is missing station assignment',
      );
    }
    if (await _userId() != userId) {
      throw const UnauthorizedFailure('Account changed');
    }
    if (device['station_id'] != null && device['station_id'] != 0) {
      return OwnedDeviceAssociation.alreadyAssigned;
    }
    final result = await stations.bindDevice(sn, stationId);
    return result.fold(
      (failure) => throw failure,
      (_) => OwnedDeviceAssociation.added,
    );
  }
}
