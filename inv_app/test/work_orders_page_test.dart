import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/features/support/presentation/pages/work_orders_page.dart';
import 'package:mocktail/mocktail.dart';

import 'helpers/pump_app.dart';

class MockDio extends Mock implements Dio {}

/// 构造 Dio Response（免 mock）
Response _resp(dynamic data) => Response(
      requestOptions: RequestOptions(path: ''),
      data: data,
    );

/// 列表接口返回体（total 可配，items 条数可配）
Map<String, dynamic> _listPayload({int total = 0, int items = 0}) {
  return {
    'code': 0,
    'message': 'success',
    'data': {
      'items': [
        for (var i = 0; i < items; i++)
          {
            'id': 'wo-$i',
            'title': '工单 $i',
            'status': 'open',
            'priority': 'medium',
            'deviceSn': 'H1CNA0013A00001$i',
            'createdAt': '2026-08-01T10:00:00Z',
          },
      ],
      'total': total,
      'page': 1,
      'page_size': 20,
    },
  };
}

void main() {
  // ---------------------------------------------------------------------------
  // 数据模型：fromJson 容错与字段双兼容
  // ---------------------------------------------------------------------------
  group('WorkOrderItem.fromJson', () {
    test('parses camelCase fields', () {
      final item = WorkOrderItem.fromJson({
        'id': '123',
        'title': '逆变器离线',
        'status': 'in_progress',
        'priority': 'high',
        'deviceSn': 'SN001',
        'createdAt': '2026-08-01T02:30:00Z',
      });
      expect(item.id, '123');
      expect(item.title, '逆变器离线');
      expect(item.status, 'in_progress');
      expect(item.priority, 'high');
      expect(item.deviceSn, 'SN001');
      expect(item.createdAt.year, 2026);
    });

    test('falls back to snake_case fields', () {
      final item = WorkOrderItem.fromJson({
        'id': 456, // 数字 id 也能解析
        'title': 'x',
        'status': 'open',
        'priority': 'low',
        'device_sn': 'SN002',
        'created_at': '2026-08-02T00:00:00Z',
      });
      expect(item.id, '456');
      expect(item.deviceSn, 'SN002');
      expect(item.createdAt.month, 8);
    });

    test('tolerates missing or malformed fields', () {
      final item = WorkOrderItem.fromJson({
        'createdAt': 'not-a-date',
      });
      expect(item.id, '');
      expect(item.title, '');
      expect(item.status, 'open'); // 缺省值
      expect(item.deviceSn, '');
      // 时间解析失败回退当前时间，不抛异常
      expect(
        DateTime.now().difference(item.createdAt).inMinutes.abs() < 2,
        isTrue,
      );
    });
  });

  group('WorkOrderDetail.fromJson', () {
    test('parses full payload with timeline and attachments', () {
      final detail = WorkOrderDetail.fromJson({
        'id': '1',
        'title': '故障检修',
        'description': '设备无法上线',
        'status': 'resolved',
        'priority': 'high',
        'deviceSn': 'SN001',
        'creatorName': '张三',
        'assigneeName': '李四',
        'templateType': 'repair',
        'resolution': '已更换通信模块',
        'slaDeadline': '2026-08-05T00:00:00Z',
        'createdAt': '2026-08-01T00:00:00Z',
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
          {'name': 'a.jpg', 'url': '/firmware/work-orders/a.jpg'},
        ],
      });
      expect(detail.resolution, '已更换通信模块');
      expect(detail.slaDeadline, isNotNull);
      expect(detail.timeline, hasLength(1));
      expect(detail.timeline.first.operator, '张三');
      expect(detail.attachments, hasLength(1));
      expect(detail.attachments.first.fullUrl, contains('/firmware/'));
    });

    test('tolerates empty payload', () {
      final detail = WorkOrderDetail.fromJson(const {});
      expect(detail.id, '');
      expect(detail.timeline, isEmpty);
      expect(detail.attachments, isEmpty);
      expect(detail.slaDeadline, isNull);
    });
  });

  test('formatWorkOrderTime outputs yyyy-MM-dd HH:mm', () {
    final t = DateTime(2026, 8, 1, 9, 5);
    expect(formatWorkOrderTime(t), '2026-08-01 09:05');
  });

  test('WorkOrderTemplate.fallback covers 4 templates', () {
    expect(WorkOrderTemplate.fallback, hasLength(4));
    expect(
      WorkOrderTemplate.fallback.map((t) => t['templateId']),
      containsAll(['repair', 'maintenance', 'inspection', 'installation']),
    );
  });

  // ---------------------------------------------------------------------------
  // 页面：列表渲染 / 统计 / 删除流程（mock Dio）
  // ---------------------------------------------------------------------------
  group('WorkOrdersPage widget', () {
    late MockDio dio;

    setUp(() async {
      dio = MockDio();
      await getIt.reset();
      getIt.registerSingleton<Dio>(dio);

      // 统计
      when(() => dio.get('/work-orders/statistics')).thenAnswer(
        (_) async => _resp({
          'code': 0,
          'data': {
            'total': 2,
            'open': 1,
            'inProgress': 1,
            'resolved': 0,
            'closed': 0,
          },
        }),
      );
      // 模板（失败回退内置）
      when(() => dio.get('/work-orders/templates')).thenAnswer(
        (_) async => _resp({'code': 0, 'data': []}),
      );
      // 设备选项
      when(
        () => dio.get(
          '/devices',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => _resp({
          'code': 0,
          'data': {
            'items': [
              {'sn': 'SN001', 'alias': '一号机'},
            ],
            'total': 1,
          },
        }),
      );
    });

    tearDown(() async {
      await getIt.reset();
    });

    testWidgets('renders list items and tab counts', (tester) async {
      when(
        () => dio.get(
          '/work-orders',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer((_) async => _resp(_listPayload(total: 2, items: 2)));

      await pumpApp(tester, const WorkOrdersPage());

      expect(find.text('工单 0'), findsOneWidget);
      expect(find.text('工单 1'), findsOneWidget);
      // Tab 统计数量：全部 (2)
      expect(find.text('全部 (2)'), findsOneWidget);
      expect(find.text('待处理 (1)'), findsOneWidget);
    });

    testWidgets('shows error toast when list load fails', (tester) async {
      when(
        () => dio.get(
          '/work-orders',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer((_) async {
        // 异步抛出：与真实 Dio 行为一致（同步 throw 会在 initState 内同步走到 toast）
        throw DioException(
          requestOptions: RequestOptions(path: '/work-orders'),
        );
      });

      await pumpApp(tester, const WorkOrdersPage());

      expect(find.text('工单加载失败，请稍后重试'), findsOneWidget);
    });

    testWidgets('delete flow calls DELETE after confirmation', (tester) async {
      when(
        () => dio.get(
          '/work-orders',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer((_) async => _resp(_listPayload(total: 1, items: 1)));
      when(() => dio.delete(any())).thenAnswer(
        (_) async => _resp({'code': 0, 'data': {'id': 'wo-0'}}),
      );

      await pumpApp(tester, const WorkOrdersPage());

      // 长按卡片弹出操作菜单
      await tester.longPress(find.text('工单 0'));
      await tester.pumpAndSettle();
      expect(find.text('删除工单'), findsWidgets);

      // 点击删除 → 二次确认弹窗（菜单可滚动，先确保可见）
      final deleteItem = find.text('删除工单').last;
      await tester.ensureVisible(deleteItem);
      await tester.tap(deleteItem);
      await tester.pumpAndSettle();
      expect(find.text('确定要删除该工单吗？删除后不可恢复'), findsOneWidget);

      // 确认删除
      final confirmButton = find.text('删除工单').last;
      await tester.ensureVisible(confirmButton);
      await tester.tap(confirmButton);
      await tester.pumpAndSettle();

      verify(() => dio.delete('/work-orders/wo-0')).called(1);
      expect(find.text('工单已删除'), findsOneWidget);
    });
  });
}
