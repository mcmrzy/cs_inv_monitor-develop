import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/services/ble/ble_device_manager.dart';

void main() {
  group('BleFrameReassembler', () {
    test('单帧（0xC0）立即返回完整消息', () {
      final r = BleFrameReassembler();
      final payload = utf8.encode('{"device_sn":"H1CNA00135000014"}');
      final result = r.feed([0xC0, ...payload]);
      expect(result, isNotNull);
      expect(utf8.decode(result!), '{"device_sn":"H1CNA00135000014"}');
    });

    test('两帧消息按序拼接', () {
      final r = BleFrameReassembler();
      final p1 = utf8.encode('{"ac":{"voltage":');
      final p2 = utf8.encode('230.1}}');

      expect(r.feed([0x80, ...p1]), isNull); // 首帧，非末帧
      final result = r.feed([0x40 | 1, ...p2]); // 末帧，序号 1
      expect(result, isNotNull);
      expect(utf8.decode(result!), '{"ac":{"voltage":230.1}}');
    });

    test('三帧消息按序拼接', () {
      final r = BleFrameReassembler();
      expect(r.feed([0x80, ...utf8.encode('aa')]), isNull);
      expect(r.feed([0x01, ...utf8.encode('bb')]), isNull); // 中间帧
      final result = r.feed([0x40 | 2, ...utf8.encode('cc')]);
      expect(utf8.decode(result!), 'aabbcc');
    });

    test('未收到首帧而收到后续帧：丢弃', () {
      final r = BleFrameReassembler();
      expect(r.feed([0x41, ...utf8.encode('xx')]), isNull);
      // 状态已重置，此后正常单帧仍可解析
      final result = r.feed([0xC0, ...utf8.encode('ok')]);
      expect(utf8.decode(result!), 'ok');
    });

    test('帧序号不连续：丢弃并等待下一首帧', () {
      final r = BleFrameReassembler();
      expect(r.feed([0x80, ...utf8.encode('aa')]), isNull);
      // 跳号（应为 1，来了 2）
      expect(r.feed([0x42, ...utf8.encode('bb')]), isNull);
      // 乱序后的数据不得污染下一条消息
      final result = r.feed([0xC0, ...utf8.encode('clean')]);
      expect(utf8.decode(result!), 'clean');
    });

    test('超过 8 帧限制：丢弃', () {
      final r = BleFrameReassembler();
      expect(r.feed([0x80, ...utf8.encode('aa')]), isNull);
      for (var i = 1; i <= 8; i++) {
        // 连续 8 个中间帧，超出 maxFrames=8 上限
        expect(r.feed([i, ...utf8.encode('aa')]), isNull);
      }
      // 重置后正常消息不受影响
      final result = r.feed([0xC0, ...utf8.encode('ok')]);
      expect(utf8.decode(result!), 'ok');
    });

    test('过短帧（<2 字节）忽略', () {
      final r = BleFrameReassembler();
      expect(r.feed([0xC0]), isNull);
      expect(r.feed([]), isNull);
    });
  });
}
