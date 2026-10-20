import 'package:flutter_test/flutter_test.dart';
import 'package:inv_app/core/utils/device_command_state.dart';

void main() {
  test('AC commands fail closed until each exact capability is advertised', () {
    expect(canSendAcCommand({}, 'ac_on'), isFalse);
    expect(canSendAcCommand({'ac_on'}, 'ac_on'), isTrue);
    expect(canSendAcCommand({'ac_on'}, 'ac_off'), isFalse);
    expect(canSendAcCommand({'set_ac_enable'}, 'ac_on'), isFalse);
    expect(canSendAcCommand({'unknown'}, 'unknown'), isFalse);
  });
  test('disabled and malformed capabilities do not enable AC controls', () {
    expect(enabledDeviceCommands([
      {'command_code': 'ac_on', 'is_enabled': false},
      {'command_code': 'ac_off', 'risk_level': 2, 'is_enabled': true},
      {'command_code': 'ac_on'},
      {'command_code': 'ac_on', 'is_enabled': null},
      {'command_code': 'ac_on', 'is_enabled': 'false'},
      {'command_code': 'ac_on', 'is_enabled': 'true'},
      {'command_code': ''},
      {'command_code': 7},
      null,
    ]), {'ac_off'});
  });
  test('submitted is terminal without claiming applied, including legacy success', () {
    expect(deviceCommandStatus({'status': 'submitted'}), 'submitted');
    expect(deviceCommandStatus({'status': 'submitted', 'stage': 'completed'}), 'submitted');
    expect(deviceCommandStatus({'status': 'success', 'stage': 'submitted'}), 'submitted');
    expect(deviceCommandStatus({'status': 'success', 'response_data': {'stage': 'submitted'}}), 'submitted');
    expect(isTerminalDeviceCommand('submitted'), isTrue);
    expect(isSuccessfulDeviceCommand('submitted'), isFalse);
    expect(deviceCommandStatusLabel('submitted'), 'control_submitted_unconfirmed');
  });
  test('ack remains nonterminal; applied and completed are successful', () {
    for (final status in ['acknowledged', 'executing']) {
      expect(isTerminalDeviceCommand(status), isFalse);
      expect(isSuccessfulDeviceCommand(status), isFalse);
      expect(deviceCommandStatusLabel(status), 'control_executing');
    }
    for (final status in ['applied', 'completed', 'success']) {
      expect(isTerminalDeviceCommand(status), isTrue);
      expect(isSuccessfulDeviceCommand(status), isTrue);
    }
    expect(deviceCommandStatus({'status': 'failed', 'stage': 'completed'}), 'failed');
  });
}
