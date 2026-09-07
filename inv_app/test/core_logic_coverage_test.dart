/// Coverage tests for pure-logic core files (SN utils, alarm mapping,
/// energy data points, organization entities, user entity).
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:inv_app/core/data/alarm_code_mapping.dart';
import 'package:inv_app/core/entities/energy_data_point.dart';
import 'package:inv_app/core/entities/organization.dart';
import 'package:inv_app/core/utils/sn_utils.dart';
import 'package:inv_app/features/auth/domain/entities/user.dart';

void main() {
  // -----------------------------------------------------------------------
  // sn_utils
  // -----------------------------------------------------------------------
  group('sn_utils', () {
    // Valid 15-char base: manufacturer=H1, country=CN, customer=A123,
    // yearMonth=8B, sequence=12345. Check digit computed by the same
    // implementation to make the test self-consistent.
    const base15 = 'H1CNA1238B12345';

    test('calculateCheckDigit returns a valid char for 15-char base', () {
      final cd = calculateCheckDigit(base15);
      expect(cd.length, 1);
      // Non-15-char input falls back to "0"
      expect(calculateCheckDigit('123'), '0');
      expect(calculateCheckDigit(''), '0');
    });

    test('parseSN accepts a fully valid SN', () {
      final sn = base15 + calculateCheckDigit(base15);
      final info = parseSN(sn);
      expect(info, isNotNull);
      expect(info!.manufacturer, 'H1');
      expect(info.country, 'CN');
      expect(info.customer, 'A123');
      expect(info.yearMonth, '8B');
      expect(info.sequence, '12345');
      expect(info.toString(), sn);
    });

    test('parseSN handles lowercase input via trim+upper', () {
      final sn = base15 + calculateCheckDigit(base15);
      expect(parseSN('  ${sn.toLowerCase()}  '), isNotNull);
    });

    test('parseSN rejects invalid lengths', () {
      expect(parseSN(''), isNull);
      expect(parseSN('12345'), isNull);
      expect(parseSN('$base15${calculateCheckDigit(base15)}X'), isNull);
    });

    test('parseSN rejects invalid manufacturer prefix', () {
      final cd = calculateCheckDigit(base15);
      expect(parseSN('X1CNA1238B12345$cd'), isNull); // X not in {H,O,S}
      expect(parseSN('H?CNA1238B12345$cd'), isNull); // non-alnum second char
    });

    test('parseSN rejects unknown country code', () {
      final cd = calculateCheckDigit(base15);
      expect(parseSN('H1XXA1238B12345$cd'), isNull);
    });

    test('parseSN rejects invalid customer grade or digits', () {
      final cd = calculateCheckDigit(base15);
      expect(parseSN('H1CNZ1238B12345$cd'), isNull); // grade Z invalid
      expect(parseSN('H1CNA1X38B12345$cd'), isNull); // non-digit customer
    });

    test('parseSN rejects invalid yearMonth or sequence', () {
      final cd = calculateCheckDigit(base15);
      expect(parseSN('H1CNA123IB12345$cd'), isNull); // I not in year charset
      expect(parseSN('H1CNA12381B2345$cd'), isNull); // month code 1 invalid
      expect(parseSN('H1CNA1238B12X45$cd'), isNull); // non-digit sequence
    });

    test('validateSNFormat / validateSN / validateCheckDigitOnly', () {
      final sn = base15 + calculateCheckDigit(base15);
      expect(validateSNFormat(sn), isTrue);
      expect(validateSNFormat('bad'), isFalse);
      expect(validateSN(sn), isTrue);
      // Tamper with a character → check digit no longer matches
      final tampered = 'H1CNA1238B12344${sn.substring(15)}';
      expect(validateSN(tampered), isFalse);
      // validateCheckDigitOnly returns true for unparsable SNs
      expect(validateCheckDigitOnly('junk'), isTrue);
      expect(validateCheckDigitOnly(tampered), isFalse);
    });

    test('formatSNForDisplay groups digits', () {
      final sn = base15 + calculateCheckDigit(base15);
      final formatted = formatSNForDisplay(sn);
      expect(formatted.split(' '), hasLength(6));
      expect(formatSNForDisplay('short'), 'short');
    });

    test('parseQRCode handles all formats', () {
      final sn = base15 + calculateCheckDigit(base15);
      final r1 = parseQRCode('SN:$sn PIN:1234');
      expect(r1, isNotNull);
      expect(r1!.sn, sn);
      expect(r1.pin, '1234');

      final r2 = parseQRCode('sn：$sn'); // full-width colon, lowercase
      expect(r2, isNotNull);
      expect(r2!.sn, sn);
      expect(r2.pin, isNull);

      final r3 = parseQRCode(sn.toLowerCase());
      expect(r3, isNotNull);
      expect(r3!.sn, sn);

      expect(parseQRCode(''), isNull);
      expect(parseQRCode('not-a-qr-code'), isNull);
      expect(parseQRCode('SN:12345'), isNull); // wrong length
    });
  });

  // -----------------------------------------------------------------------
  // alarm_code_mapping
  // -----------------------------------------------------------------------
  group('alarm_code_mapping', () {
    test('getEntry returns entries for known codes', () {
      expect(AlarmCodeMapping.getEntry(0), isNotNull);
      expect(AlarmCodeMapping.getEntry(12), isNotNull);
      expect(AlarmCodeMapping.getEntry(999), isNull);
    });

    test('getNameZh / getLocalizedName', () {
      expect(AlarmCodeMapping.getNameZh(0), contains('恢复'));
      expect(AlarmCodeMapping.getNameZh(999), contains('未知'));
      expect(AlarmCodeMapping.getLocalizedName(1, 'zh'), contains('过温'));
      expect(AlarmCodeMapping.getLocalizedName(1, 'en'), contains('over-temperature'));
      expect(AlarmCodeMapping.getLocalizedName(999, 'zh'), contains('未知'));
      expect(AlarmCodeMapping.getLocalizedName(999, 'en'), contains('Unknown'));
    });

    test('getDescription / getSuggestion fall back for unknown codes', () {
      expect(AlarmCodeMapping.getDescription(2), contains('电池组电压'));
      expect(AlarmCodeMapping.getDescription(999), contains('暂无'));
      expect(AlarmCodeMapping.getSuggestion(3), contains('减少'));
      expect(AlarmCodeMapping.getSuggestion(999), contains('联系安装商'));
    });

    test('search matches by zh name, en name, tags and code', () {
      expect(AlarmCodeMapping.search('过温'), isNotEmpty);
      expect(AlarmCodeMapping.search('battery'), isNotEmpty);
      expect(AlarmCodeMapping.search('电池'), isNotEmpty);
      expect(AlarmCodeMapping.search('5'), isNotEmpty);
      expect(AlarmCodeMapping.search('zzzz-no-match-zzzz'), isEmpty);
    });

    test('getBySeverity groups entries', () {
      expect(AlarmCodeMapping.getBySeverity('fault'), isNotEmpty);
      expect(AlarmCodeMapping.getBySeverity('warning'), isNotEmpty);
      expect(AlarmCodeMapping.getBySeverity('info'), isNotEmpty);
      expect(AlarmCodeMapping.getBySeverity('normal'), isNotEmpty);
      expect(AlarmCodeMapping.getBySeverity('nope'), isEmpty);
    });

    test('AlarmCodeEntry json roundtrip and localization', () {
      final original = AlarmCodeMapping.getEntry(1)!;
      final json = original.toJson();
      final restored = AlarmCodeEntry.fromJson(json);
      expect(restored.code, original.code);
      expect(restored.nameZh, original.nameZh);
      expect(restored.tags, original.tags);
      expect(restored.getLocalizedName('zh'), original.nameZh);
      expect(restored.getLocalizedName('en'), original.nameEn);
      // English details come from the static map for known codes
      expect(restored.getLocalizedDescription('en'), isNotEmpty);
      expect(restored.getLocalizedPossibleCause('en'), isNotEmpty);
      expect(restored.getLocalizedSuggestion('en'), isNotEmpty);
      expect(restored.getLocalizedDescription('zh'), original.description);
    });
  });

  // -----------------------------------------------------------------------
  // energy_data_point
  // -----------------------------------------------------------------------
  group('energy_data_point', () {
    test('fromJson maps known fields and defaults missing ones', () {
      final p = EnergyDataPoint.fromJson({
        'time': '12:00',
        'energy_produce': 1.5,
        'battery_charge': 2.5,
        'grid_export': 3,
      });
      expect(p.time, '12:00');
      expect(p.pvEnergy, 1.5);
      expect(p.batteryCharge, 2.5);
      expect(p.gridExport, 3);
      expect(p.batteryDischarge, 0);
      expect(p.dailyPv, 0);
      expect(EnergyDataPoint.fromJson({}).time, '');
    });

    test('fromStationStats hour mode uses daily_* cumulative values', () {
      final p = EnergyDataPoint.fromStationStats({
        'time': '14:00',
        'energy_produce': 500, // W (average power)
        'energy_consume': 400,
        'battery_charge': 100,
        'battery_discharge': 60,
        'grid_import': 30,
        'grid_export': 20,
        'daily_pv': 12.5,
        'daily_charge': 8.0,
        'daily_discharge': 5.0,
        'daily_load': 9.5,
      });
      expect(p.pvEnergy, 12.5); // kWh from daily_pv
      expect(p.batteryCharge, 8.0);
      expect(p.inverterOutput, 9.5);
      expect(p.pvPower, 500); // W from raw power
      expect(p.gridPower, 10); // grid_import - grid_export
    });

    test('fromStationStats day/month mode uses top-level fields', () {
      final p = EnergyDataPoint.fromStationStats({
        'time': '06-01',
        'energy_produce': 20.0, // kWh
        'battery_charge': 10.0,
        'battery_discharge': 6.0,
        'feed_energy': 15.0, // alias for grid_export
      });
      expect(p.pvEnergy, 20.0);
      expect(p.batteryCharge, 10.0);
      expect(p.gridExport, 15.0);
      expect(p.pvPower, 0); // no daily_* fields → power disabled
      expect(p.gridPower, 0);
    });

    test('toJson roundtrips core fields', () {
      final p = EnergyDataPoint.fromJson({
        'time': '08:00',
        'energy_produce': 4.2,
        'grid_import': 1.1,
      });
      final json = p.toJson();
      expect(json['time'], '08:00');
      expect(json['energy_produce'], 4.2);
      expect(json['grid_import'], 1.1);
    });

    test('EnergySummary.fromDataPoints sums values', () {
      final points = [
        EnergyDataPoint.fromJson({'time': 'a', 'energy_produce': 1, 'battery_charge': 2}),
        EnergyDataPoint.fromJson({'time': 'b', 'energy_produce': 3, 'battery_charge': 4}),
      ];
      final s = EnergySummary.fromDataPoints(points);
      expect(s.pvTotal, 4);
      expect(s.batteryChargeTotal, 6);
      expect(s.gridImportTotal, 0);
    });

    test('EnergySummary.fromDataPointsWithPeriod day vs sum modes', () {
      // Empty list → default summary
      final empty = EnergySummary.fromDataPointsWithPeriod([], 'month');
      expect(empty.pvTotal, 0);

      final points = [
        EnergyDataPoint.fromJson({
          'time': '10:00',
          'energy_produce': 1,
          'daily_pv': 5,
          'daily_load': 6,
        }),
        EnergyDataPoint.fromJson({
          'time': '11:00',
          'energy_produce': 2,
          'daily_pv': 9,
          'daily_load': 10,
        }),
      ];
      // day mode: last point's cumulative values
      final day = EnergySummary.fromDataPointsWithPeriod(points, 'day');
      expect(day.pvTotal, 9);
      expect(day.inverterOutputTotal, 10);
      // month/year mode: plain sum of pvEnergy
      final month = EnergySummary.fromDataPointsWithPeriod(points, 'month');
      expect(month.pvTotal, 3);
    });
  });

  // -----------------------------------------------------------------------
  // organization entities
  // -----------------------------------------------------------------------
  group('organization', () {
    test('Organization json roundtrip and copyWith', () {
      final org = Organization.fromJson({
        'id': 7,
        'name': 'Org A',
        'description': 'desc',
        'member_count': 3,
        'device_count': 5,
        'created_at': '2026-01-01',
      });
      expect(org.id, 7);
      expect(org.memberCount, 3);
      expect(org.toJson()['device_count'], 5);
      final copy = org.copyWith(name: 'Org B', memberCount: 10);
      expect(copy.name, 'Org B');
      expect(copy.memberCount, 10);
      expect(copy.id, 7); // unchanged
    });

    test('OrgMemberRole extension maps display names and api values', () {
      expect(OrgMemberRole.orgAdmin.displayName, '组织管理员');
      expect(OrgMemberRole.agent.displayName, '代理商');
      expect(OrgMemberRole.distributor.displayName, '分销商');
      expect(OrgMemberRole.installer.displayName, '安装商');
      expect(OrgMemberRole.customer.displayName, '终端用户');
      expect(OrgMemberRole.orgAdmin.apiValue, 'org_admin');
      expect(OrgMemberRole.customer.apiValue, 'customer');
      expect(OrgMemberRoleExtension.fromApiValue('INSTALLER'), OrgMemberRole.installer);
      expect(OrgMemberRoleExtension.fromApiValue('unknown'), OrgMemberRole.customer);
    });

    test('OrganizationMember json roundtrip', () {
      final m = OrganizationMember.fromJson({
        'user_id': 1,
        'email': 'a@b.c',
        'phone': '138',
        'role': 'agent',
        'pending': true,
        'invited_at': '2026-02-01',
      });
      expect(m.userId, 1);
      expect(m.role, OrgMemberRole.agent);
      expect(m.pending, isTrue);
      expect(m.toJson()['role'], 'agent');
    });

    test('OrganizationInvitation fromJson defaults', () {
      final inv = OrganizationInvitation.fromJson({
        'id': 9,
        'email': 'x@y.z',
        'role_codes': ['agent', 'installer'],
      });
      expect(inv.id, 9);
      expect(inv.status, 'pending');
      expect(inv.roleCodes, ['agent', 'installer']);
      expect(inv.organizationId, isNull);
    });

    test('DeviceTransferRequest json roundtrip', () {
      final r = DeviceTransferRequest.fromJson({
        'id': 3,
        'device_sn': 'SN001',
        'device_model': 'CS6K2',
        'source_org_id': 1,
        'target_org_id': 2,
        'requester_email': 'r@t.c',
        'status': 'pending',
        'reason': 'relocation',
      });
      expect(r.deviceSn, 'SN001');
      expect(r.status, 'pending');
      expect(r.toJson()['source_org_id'], 1);
      expect(r.toJson()['reason'], 'relocation');
    });
  });

  // -----------------------------------------------------------------------
  // user entity
  // -----------------------------------------------------------------------
  group('user', () {
    test('fromJson detects admin via is_system_admin flag', () {
      final u = User.fromJson({'id': 1, 'phone': '138', 'is_system_admin': true, 'status': 1});
      expect(u.isSystemAdmin, isTrue);
    });

    test('fromJson detects admin via legacy role == 0', () {
      final u = User.fromJson({'id': 2, 'phone': '139', 'role': 0, 'status': 1});
      expect(u.isSystemAdmin, isTrue);
    });

    test('fromJson filters permissions to strings and handles status object', () {
      final u = User.fromJson({
        'id': 3,
        'phone': '137',
        'permissions': ['device:view', 42, 'alarm:view'],
        'status': {'status_id': 3},
        'region_name': '广东',
      });
      expect(u.permissions, ['device:view', 'alarm:view']);
      expect(u.status, 3);
      expect(u.region, '广东');
    });

    test('roleName and hasPermission', () {
      final admin = User.fromJson({'id': 1, 'phone': '1', 'is_system_admin': true, 'status': 1});
      expect(admin.roleName, 'System Admin');
      expect(admin.hasPermission('anything'), isTrue);

      final member = User.fromJson({
        'id': 2,
        'phone': '2',
        'status': 1,
        'permissions': ['device:view'],
      });
      expect(member.roleName, 'Member');
      expect(member.hasPermission('device:view'), isTrue);
      expect(member.hasPermission('ota:push'), isFalse);
    });

    test('LoginResponse.fromJson extracts token and permissions', () {
      final r = LoginResponse.fromJson({
        'access_token': 'tok123',
        'expires_in': 7200,
        'permissions': ['a', 1],
        'user': {'id': 5, 'phone': '136', 'status': 1},
      });
      expect(r.token, 'tok123');
      expect(r.permissions, ['a']);
      expect(r.user.id, 5);
      // Fallback token fields
      final r2 = LoginResponse.fromJson(
        {'token': 't2', 'user': <String, dynamic>{}},
      );
      expect(r2.token, 't2');
    });
  });
}
