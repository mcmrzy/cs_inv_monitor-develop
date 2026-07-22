const snLength = 16;

const _yearCharset = '123456789ABCDEFGHJKLMNPQRSTUVWXYZ';

const _monthCodes = [
  '1',
  '2',
  '3',
  '4',
  '5',
  '6',
  '7',
  '8',
  '9',
  'A',
  'B',
  'C',
];

const _validCountryCodes = {
  'AF',
  'AL',
  'DZ',
  'AD',
  'AO',
  'AG',
  'AR',
  'AM',
  'AU',
  'AT',
  'AZ',
  'BS',
  'BH',
  'BD',
  'BB',
  'BY',
  'BE',
  'BZ',
  'BJ',
  'BT',
  'BO',
  'BA',
  'BW',
  'BR',
  'BN',
  'BG',
  'BF',
  'BI',
  'KH',
  'CM',
  'CA',
  'CV',
  'CF',
  'TD',
  'CL',
  'CN',
  'CO',
  'KM',
  'CG',
  'CR',
  'CI',
  'HR',
  'CU',
  'CY',
  'CZ',
  'DK',
  'DJ',
  'DM',
  'DO',
  'EC',
  'EG',
  'SV',
  'GQ',
  'ER',
  'EE',
  'ET',
  'FJ',
  'FI',
  'FR',
  'GA',
  'GM',
  'GE',
  'DE',
  'GH',
  'GR',
  'GD',
  'GT',
  'GN',
  'GW',
  'GY',
  'HT',
  'HN',
  'HU',
  'IS',
  'IN',
  'ID',
  'IR',
  'IQ',
  'IE',
  'IL',
  'IT',
  'JM',
  'JP',
  'JO',
  'KZ',
  'KE',
  'KI',
  'KP',
  'KR',
  'KW',
  'KG',
  'LA',
  'LV',
  'LB',
  'LS',
  'LR',
  'LY',
  'LI',
  'LT',
  'LU',
  'MK',
  'MG',
  'MW',
  'MY',
  'MV',
  'ML',
  'MT',
  'MH',
  'MR',
  'MU',
  'MX',
  'FM',
  'MD',
  'MC',
  'MN',
  'ME',
  'MA',
  'MZ',
  'MM',
  'NA',
  'NR',
  'NP',
  'NL',
  'NZ',
  'NI',
  'NE',
  'NG',
  'NO',
  'OM',
  'PK',
  'PW',
  'PS',
  'PA',
  'PG',
  'PY',
  'PE',
  'PH',
  'PL',
  'PT',
  'QA',
  'RO',
  'RU',
  'RW',
  'KN',
  'LC',
  'VC',
  'WS',
  'SM',
  'ST',
  'SA',
  'SN',
  'RS',
  'SC',
  'SL',
  'SG',
  'SK',
  'SI',
  'SB',
  'SO',
  'ZA',
  'SS',
  'ES',
  'LK',
  'SD',
  'SR',
  'SE',
  'CH',
  'SY',
  'TW',
  'TJ',
  'TZ',
  'TH',
  'TL',
  'TG',
  'TO',
  'TT',
  'TN',
  'TR',
  'TM',
  'TV',
  'UG',
  'UA',
  'AE',
  'GB',
  'US',
  'UY',
  'UZ',
  'VU',
  'VE',
  'VN',
  'YE',
  'ZM',
  'ZW',
  '99',
  'ZZ',
};

class SNInfo {
  final String manufacturer;
  final String country;
  final String customer;
  final String yearMonth;
  final String sequence;
  final String checkDigit;

  const SNInfo({
    required this.manufacturer,
    required this.country,
    required this.customer,
    required this.yearMonth,
    required this.sequence,
    required this.checkDigit,
  });

  @override
  String toString() {
    return '$manufacturer$country$customer$yearMonth$sequence$checkDigit';
  }
}

int _crc16modbus(String data) {
  int crc = 0xFFFF;
  for (int i = 0; i < data.length; i++) {
    crc ^= data.codeUnitAt(i);
    for (int j = 0; j < 8; j++) {
      if ((crc & 1) != 0) {
        crc = (crc >> 1) ^ 0xA001;
      } else {
        crc = crc >> 1;
      }
    }
  }
  return crc;
}

String _valueToChar(int v) {
  if (v >= 0 && v <= 9) return String.fromCharCode(0x30 + v);
  if (v >= 10 && v <= 35) return String.fromCharCode(0x41 + v - 10);
  return '0';
}

String calculateCheckDigit(String base15) {
  if (base15.length != 15) return '0';
  final crc = _crc16modbus(base15);
  final lo = crc & 0xFF;
  return _valueToChar(lo % 36);
}

SNInfo? parseSN(String sn) {
  final raw = sn.toUpperCase().trim();
  if (raw.length != snLength) return null;

  final manufacturer = raw.substring(0, 2);
  final country = raw.substring(2, 4);
  final customer = raw.substring(4, 8);
  final yearMonth = raw.substring(8, 10);
  final sequence = raw.substring(10, 15);
  final checkDigit = raw.substring(15, 16);

  final mf0 = manufacturer[0];
  if (mf0 != 'H' && mf0 != 'O' && mf0 != 'S') return null;
  final mf1 = manufacturer[1];
  if (!((mf1.codeUnitAt(0) >= 0x30 && mf1.codeUnitAt(0) <= 0x39) ||
      (mf1.codeUnitAt(0) >= 0x41 && mf1.codeUnitAt(0) <= 0x5A))) {
    return null;
  }

  if (!_validCountryCodes.contains(country)) return null;

  final custGrade = customer[0];
  if (custGrade != 'A' &&
      custGrade != 'B' &&
      custGrade != 'C' &&
      custGrade != 'X' &&
      custGrade != 'P') {
    return null;
  }
  for (int i = 1; i < 4; i++) {
    final ch = customer[i].codeUnitAt(0);
    if (ch < 0x30 || ch > 0x39) return null;
  }

  if (!_yearCharset.contains(yearMonth[0])) return null;
  if (!_monthCodes.contains(yearMonth[1])) return null;

  for (int i = 0; i < 5; i++) {
    final ch = sequence[i].codeUnitAt(0);
    if (ch < 0x30 || ch > 0x39) return null;
  }

  final cd = checkDigit.codeUnitAt(0);
  if (cd < 0x30 || cd > 0x5A || (cd > 0x39 && cd < 0x41)) {
    return null;
  }

  return SNInfo(
    manufacturer: manufacturer,
    country: country,
    customer: customer,
    yearMonth: yearMonth,
    sequence: sequence,
    checkDigit: checkDigit,
  );
}

bool validateSNFormat(String sn) {
  return parseSN(sn) != null;
}

bool validateSN(String sn) {
  final info = parseSN(sn);
  if (info == null) return false;
  final base15 =
      '${info.manufacturer}${info.country}${info.customer}${info.yearMonth}${info.sequence}';
  final expected = calculateCheckDigit(base15);
  return expected == info.checkDigit;
}

bool validateCheckDigitOnly(String sn) {
  final info = parseSN(sn);
  if (info == null) return true;
  final base15 =
      '${info.manufacturer}${info.country}${info.customer}${info.yearMonth}${info.sequence}';
  final expected = calculateCheckDigit(base15);
  return expected == info.checkDigit;
}

String formatSNForDisplay(String sn) {
  if (sn.length != snLength) return sn;
  return '${sn.substring(0, 2)} ${sn.substring(2, 4)} ${sn.substring(4, 8)} ${sn.substring(8, 10)} ${sn.substring(10, 15)} ${sn.substring(15, 16)}';
}

class QRScanResult {
  final String sn;
  final String? pin;

  const QRScanResult({required this.sn, this.pin});
}

QRScanResult? parseQRCode(String raw) {
  final trimmed = raw.trim();

  final r1 = RegExp(
    r'^SN\s*[:：]\s*([A-Za-z0-9]{16})(?:\s+PIN\s*[:：]\s*([A-Za-z0-9]+))?\s*$',
    caseSensitive: false,
  );
  final m = r1.firstMatch(trimmed);
  if (m != null) {
    return QRScanResult(sn: m.group(1)!.toUpperCase(), pin: m.group(2));
  }

  final r2 = RegExp(r'^([A-Za-z0-9]{16})$');
  if (r2.hasMatch(trimmed)) {
    return QRScanResult(sn: trimmed.toUpperCase());
  }

  return null;
}
