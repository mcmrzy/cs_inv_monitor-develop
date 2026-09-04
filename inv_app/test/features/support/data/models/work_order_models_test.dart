import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/features/support/data/models/work_order_models.dart';

void main() {
  group('WorkOrderDetail.fromJson', () {
    test('keeps camelCase and snake_case API compatibility', () {
      final detail = WorkOrderDetail.fromJson({
        'id': 42,
        'title': '逆变器离线',
        'device_sn': 'SN-001',
        'creatorName': '张三',
        'assignee_name': '李四',
        'template_type': 'repair',
        'created_at': '2026-08-01T00:00:00Z',
        'updatedAt': '2026-08-02T00:00:00Z',
        'timeline': [
          {
            'status': 'open',
            'operator': '张三',
            'remark': 'created',
            'timestamp': '2026-08-01T00:00:00Z',
          },
        ],
        'attachments': [
          {'name': 'fault.jpg', 'url': '/firmware/fault.jpg'},
        ],
      });

      expect(detail.id, '42');
      expect(detail.deviceSn, 'SN-001');
      expect(detail.creatorName, '张三');
      expect(detail.assigneeName, '李四');
      expect(detail.templateType, 'repair');
      expect(detail.timeline.single.status, 'open');
      expect(detail.attachments.single.name, 'fault.jpg');
    });
  });

  test('WorkOrderItem retains tolerant defaults', () {
    final before = DateTime.now();
    final item = WorkOrderItem.fromJson({'createdAt': 'invalid'});
    final after = DateTime.now();

    expect(item.id, '');
    expect(item.status, 'open');
    expect(item.createdAt.isBefore(before), isFalse);
    expect(item.createdAt.isAfter(after), isFalse);
  });

  test('formatWorkOrderTime keeps the existing local display format', () {
    final utc = DateTime.utc(2026, 8, 1, 1, 5);
    final local = utc.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    final expected = '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';

    expect(formatWorkOrderTime(utc), expected);
  });

  test('relative attachment URL is expanded with the configured API host', () {
    const attachment = WorkOrderAttachment(
      name: 'fault.jpg',
      url: '/firmware/fault.jpg',
    );

    expect(attachment.fullUrl, endsWith('/firmware/fault.jpg'));
    expect(attachment.fullUrl, isNot(contains('/api/v1/firmware')));
  });
}
