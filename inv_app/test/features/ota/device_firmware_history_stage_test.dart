import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/features/ota/domain/entities/device_firmware_history.dart';
import 'package:inv_app/l10n/app_en.dart' as en_catalog;
import 'package:inv_app/l10n/app_zh.dart' as zh_catalog;

/// 设备端能上报的全部 OTA 阶段（固件 ota_state_name()）。
/// 设备新增状态时这里应当先红，提醒补 UI 文案 —— 否则界面会直接显示英文原文，
/// 用户看到的是 "booting" 这种内部词。
const deviceStages = <String>[
  'accepted',
  'downloading',
  'receiving',
  'verifying',
  'installing',
  'rebooting',
  'succeeded',
  'failed',
  'rolled_back',
];

void main() {
  group('DeviceFirmwareHistory.stage', () {
    test('fromJson 解析 stage，缺失时为空串', () {
      final withStage = DeviceFirmwareHistory.fromJson({
        'id': 1,
        'device_sn': 'SN1',
        'target_chip': 'arm',
        'old_version': '1.0.0',
        'firmware_version': '1.0.1',
        'status': 'upgrading',
        'stage': 'installing',
        'changelog': '',
        'updated_at': '2026-09-14T00:00:00Z',
      });
      expect(withStage.stage, 'installing');

      final legacy = DeviceFirmwareHistory.fromJson({
        'id': 2,
        'device_sn': 'SN1',
        'status': 'upgrading',
      });
      expect(legacy.stage, isEmpty, reason: '旧数据没有 stage 字段，应回落为空串');
    });

    test('每个设备阶段都有中英文案（receiving 复用 downloading）', () {
      for (final stage in deviceStages) {
        final key = 'upgrade_stage_${stage == 'receiving' ? 'downloading' : stage}';
        expect(zh_catalog.zh.containsKey(key), isTrue,
            reason: '缺少中文文案: $key');
        expect(en_catalog.en.containsKey(key), isTrue,
            reason: '缺少英文文案: $key');
      }
    });
  });
}
