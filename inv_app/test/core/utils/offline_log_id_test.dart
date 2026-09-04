import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/utils/offline_log_id.dart';

void main() {
  group('newOfflineLogId', () {
    test('生成 UUID v4 格式且唯一', () {
      final id1 = newOfflineLogId();
      final id2 = newOfflineLogId();
      expect(
        RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
            .hasMatch(id1),
        isTrue,
      );
      expect(id1, isNot(id2));
    });
  });
}
