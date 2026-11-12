import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/services/ble/ble_adapter.dart';
import 'package:inv_app/core/services/ble/ble_device_manager.dart';
import 'package:inv_app/core/services/ble/modbus_panel_ble.dart';
import 'package:mocktail/mocktail.dart';

class _Adapter extends Mock implements BleAdapter {}

class _Connection extends Mock
    implements BleGattConnection, BleNotificationReadiness {}

class _Keys extends Mock implements BleDeviceKeyStore {}

void main() {
  for (final scenario in [
    (23, false, false),
    (185, false, false),
    (247, false, false),
    (256, false, false),
    (512, false, false),
    (23, true, false),
    (23, false, true),
  ]) {
    final (mtu, rejectHandshake, panel) = scenario;
    test(
        'MTU $mtu bounded frames, rejected handshake=$rejectHandshake, panel=$panel',
        () async {
      final adapter = _Adapter();
      final connection = _Connection();
      final keys = _Keys();
      late BleDeviceState Function() sessionState;
      final results = StreamController<List<int>>.broadcast(sync: true);
      final telemetry = StreamController<List<int>>.broadcast(sync: true);
      var notificationsEnabled = false;
      when(() => connection.notificationsReady(any(), any()))
          .thenAnswer((_) async {
        await Future<void>.delayed(Duration.zero);
        notificationsEnabled = true;
      });
      final sent = <List<int>>[];
      final requests = <Map<String, dynamic>>[];
      final incoming = <int>[];
      const sid = '0123456789abcdef0123456789abcdef';
      when(() => adapter.connect(any(), autoConnect: any(named: 'autoConnect')))
          .thenAnswer((_) async => connection);
      when(() => connection.mtuNow).thenReturn(mtu);
      when(() => connection.linkState).thenAnswer((_) => const Stream.empty());
      when(() => connection.read(BleCtProtocol.provisioningServiceUuid,
              BleCtProtocol.provisioningSnCharUuid))
          .thenAnswer((_) async => utf8.encode('H1ZZX00139000081'));
      when(() => connection.read(
              BleCtProtocol.serviceUuid, BleCtProtocol.infoCharUuid))
          .thenAnswer((_) async => utf8.encode(jsonEncode({
                'v': 2,
                'type': 'info',
                'session_id': sid,
                'body': {
                  'device_sn': 'H1ZZX00139000081',
                  'proto_version': 2,
                  'capabilities': [
                    'info',
                    'telemetry',
                    'control',
                    'framing_v1',
                    'direct_control_v1'
                  ]
                },
              })));
      when(() => connection.subscribe(any(), any())).thenAnswer((call) =>
          call.positionalArguments[1] == BleCtProtocol.cmdResultCharUuid
              ? results.stream
              : call.positionalArguments[1] == BleCtProtocol.telemetryCharUuid
                  ? telemetry.stream
                  : const Stream.empty());
      when(() => keys.read(any())).thenAnswer((_) async => null);
      when(() => connection.disconnect()).thenAnswer((_) async {});
      when(() => connection.write(
              BleCtProtocol.serviceUuid, BleCtProtocol.commandCharUuid, any()))
          .thenAnswer((call) async {
        final frame = List<int>.from(call.positionalArguments[2] as List<int>);
        sent.add(frame);
        expect(notificationsEnabled, isTrue);
        expect(frame.length, lessThanOrEqualTo(mtu - 3));
        if (requests.isEmpty)
          expect(sessionState(), isNot(BleDeviceState.ready));
        if (frame.first & 0x80 != 0) incoming.clear();
        incoming.addAll(frame.skip(1));
        if (frame.first & 0x40 == 0) return;
        final request =
            (jsonDecode(utf8.decode(incoming)) as Map).cast<String, dynamic>();
        requests.add(request);
        final body = (request['body'] as Map).cast<String, dynamic>();
        final isOpen = body['action'] == 'open_session';
        final params = (body['params'] as Map?) ?? const {};
        final panelInfo = panel && body['action'] == 'panel_info';
        final actualPanel = panel && params['param_id'] == 'panel_4101';
        final submitted = actualPanel && params['value'] == 1;
        final response = utf8.encode(jsonEncode({
          'v': 2,
          'type': 'control.result',
          'session_id': sid,
          'in_reply_to': request['message_id'],
          'body': {
            'command_id': body['command_id'],
            'status': isOpen || panelInfo
                ? 'applied'
                : actualPanel
                    ? (submitted ? 'submitted' : 'applied')
                    : 'saved',
            'actual': isOpen
                ? {
                    'framing_v1': !rejectHandshake,
                    'direct_control_v1': true,
                    'panel_api_v1': panel
                  }
                : panelInfo
                    ? {
                        'model': '3KU',
                        'count': 54,
                        'context': 12,
                        'online': true,
                      }
                    : actualPanel
                        ? {
                            'param_id': 'panel_4101',
                            if (!submitted) 'value': params['value'],
                            'observed': !submitted,
                            'submitted': true,
                          }
                        : {'param_id': 'set_output_voltage', 'value': 230},
            'saved': !isOpen,
            'submitted': !isOpen,
            'observed': false,
            'parameter_revision': 2,
            'error': null
          },
        }));
        for (var offset = 0, seq = 0; offset < response.length; seq++) {
          final end = (offset + mtu - 4).clamp(0, response.length);
          final header = seq |
              (offset == 0 ? 0x80 : 0) |
              (end == response.length ? 0x40 : 0);
          results.add([header, ...response.sublist(offset, end)]);
          offset = end;
        }
      });
      final session = BleDeviceSession(
          adapter: adapter, macAddress: 'test', keyStore: keys);
      sessionState = () => session.state;
      try {
        if (rejectHandshake) {
          await expectLater(
              session.connect(autoReconnect: false),
              throwsA(isA<BleCommandException>()
                  .having((e) => e.code, 'code', 'PROTOCOL_NOT_READY')));
          expect(session.state, BleDeviceState.disconnected);
          verify(() => connection.disconnect()).called(1);
          return;
        }
        await session.connect(autoReconnect: false);
        expect(requests, isNotEmpty);
        expect(requests.first['body']['action'], 'open_session');
        expect(session.state, BleDeviceState.ready);
        expect(session.supportsPanelApi, panel);
        await expectLater(
            session.sendCommand(
                'set_param', {'param_id': 'set_output_voltage', 'value': 230}),
            throwsA(isA<BleCommandException>()
                .having((e) => e.code, 'code', 'SAVED_UNCONFIRMED')));
        expect(requests, hasLength(2));
        if (panel) {
          final api = ModbusPanelBle(session, english: true);
          expect((await api.info()).model, '3KU');
          expect(requests.last['body']['params']['en'], isTrue);
          expect(await api.write('panel_4101', 0, 12),
              ModbusPanelWriteOutcome.applied);
          expect(await api.write('panel_4101', 1, 12),
              ModbusPanelWriteOutcome.submitted);
          expect(requests.last['body']['params']['context'], 12);
          expect(await api.write('panel_4101', 0, 12, bmsSuggestion: true),
              ModbusPanelWriteOutcome.applied);
          expect(requests.last['body']['params']['bms_suggestion'], isTrue);
        }
        await expectLater(
            session.sendCommand('power_off'),
            throwsA(isA<BleCommandException>()
                .having((e) => e.code, 'code', 'UNSUPPORTED_ACTION')));
        expect(requests, hasLength(panel ? 6 : 2));
        expect(sent, isNotEmpty);
        await session.disconnect();
        when(() => connection.read(
                BleCtProtocol.serviceUuid, BleCtProtocol.infoCharUuid))
            .thenAnswer((_) async => utf8.encode(jsonEncode({
                  'v': 2,
                  'type': 'info',
                  'session_id': sid,
                  'body': {
                    'device_sn': 'H1ZZX00139000081',
                    'proto_version': 2,
                    'capabilities': ['telemetry', 'control']
                  },
                })));
        await session.connect(autoReconnect: false);
        final received = <Map<String, dynamic>>[];
        final dataSub = session.telemetry.listen(received.add);
        final bytes = utf8.encode('{"test":123}');
        for (var i = 0; i < 9; i++) {
          telemetry.add([
            i | (i == 0 ? 0x80 : 0) | (i == 8 ? 0x40 : 0),
            ...bytes.sublist(i, i == 8 ? bytes.length : i + 1)
          ]);
        }
        await Future<void>.delayed(Duration.zero);
        expect(received, isEmpty,
            reason: 'legacy connection must restore 8-frame limit');
        await dataSub.cancel();
      } finally {
        await session.dispose();
        await results.close();
        await telemetry.close();
      }
    });
  }
  test('extended reassembly bounds and recovery', () {
    final parser = BleFrameReassembler(maxFrames: 64, maxBytes: 512);
    expect(parser.feed([0x81, 1], nowMs: 0), isNull);
    expect(parser.feed([0x80, 1], nowMs: 1), isNull);
    expect(parser.feed([0x02, 2], nowMs: 2), isNull);
    expect(parser.feed([0xc0, 3], nowMs: 6000), [3]);
    expect(parser.feed([0x80, 1], nowMs: 6001), isNull);
    expect(parser.feed([0x41, 2], nowMs: 12000), isNull);
    expect(parser.feed([0xc0, 4], nowMs: 12001), [4]);
    expect(parser.feed([0xc0, ...List.filled(513, 0)], nowMs: 12002), isNull);
    for (var i = 0; i < 64; i++) {
      final result = parser.feed(
          [i | (i == 0 ? 0x80 : 0) | (i == 63 ? 0x40 : 0), i],
          nowMs: 13000 + i);
      expect(result,
          i == 63 ? orderedEquals(List.generate(64, (i) => i)) : isNull);
    }
  });
}
