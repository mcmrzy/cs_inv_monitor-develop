import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

class MDNSDevice {
  final String name;
  final String host;
  final int port;
  final String? sn;

  MDNSDevice({
    required this.name,
    required this.host,
    required this.port,
    this.sn,
  });
}

class MDNSDiscoveryService {
  static const int _mdnsPort = 5353;
  static const String _mdnsAddress = '224.0.0.251';
  static const Duration _queryInterval = Duration(seconds: 1);
  static const int _maxQueries = 3;

  Future<List<MDNSDevice>> discoverServices({
    String serviceType = '_http._tcp',
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      final devices = <MDNSDevice>[];
      final completer = Completer<List<MDNSDevice>>();
      final seenNames = <String>{};

      RawDatagramSocket socket;
      Timer? timeoutTimer;
      int queryCount = 0;

      try {
        socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, _mdnsPort);
        socket.multicastLoopback = false;
        socket.joinMulticast(InternetAddress(_mdnsAddress));
      } catch (_) {
        try {
          socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
        } catch (_) {
          return [];
        }
      }

      timeoutTimer = Timer(timeout, () {
        if (!completer.isCompleted) {
          completer.complete(devices);
        }
      });

      void sendQuery() {
        if (queryCount >= _maxQueries || completer.isCompleted) return;
        queryCount++;

        final query = _buildMDNSQuery(serviceType);
        socket.send(query, InternetAddress(_mdnsAddress), _mdnsPort);
      }

      sendQuery();
      final queryTimer = Timer.periodic(_queryInterval, (_) => sendQuery());

      socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket.receive();
          if (datagram == null) return;

          try {
            final parsed = _parseMDNSResponse(datagram.data, serviceType);
            for (final device in parsed) {
              if (!seenNames.contains(device.name)) {
                seenNames.add(device.name);
                devices.add(device);
              }
            }
          } catch (_) {}
        }
      });

      final result = await completer.future;

      queryTimer.cancel();
      timeoutTimer.cancel();
      socket.close();

      return result;
    } catch (_) {
      return [];
    }
  }

  Future<List<MDNSDevice>> discoverInvServices({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final httpDevices = await discoverServices(
      serviceType: '_http._tcp',
      timeout: timeout,
    );

    final invDevices = await discoverServices(
      serviceType: '_inv._tcp',
      timeout: timeout,
    );

    final allDevices = <MDNSDevice>[...httpDevices];
    final seenNames = httpDevices.map((d) => d.name).toSet();

    for (final device in invDevices) {
      if (!seenNames.contains(device.name)) {
        seenNames.add(device.name);
        allDevices.add(device);
      }
    }

    return allDevices;
  }

  Uint8List _buildMDNSQuery(String serviceType) {
    final builder = BytesBuilder();

    builder.add([0x00, 0x00]);
    builder.add([0x00, 0x00]);
    builder.add([0x00, 0x01]);
    builder.add([0x00, 0x00]);
    builder.add([0x00, 0x00]);
    builder.add([0x00, 0x00]);

    _writeName(builder, serviceType);
    _writeName(builder, 'local');

    builder.add([0x00, 0x0C]);
    builder.add([0x00, 0x01]);

    return builder.toBytes();
  }

  void _writeName(BytesBuilder builder, String name) {
    final parts = name.split('.');
    for (final part in parts) {
      final bytes = part.codeUnits;
      builder.addByte(bytes.length);
      builder.add(bytes);
    }
  }

  List<MDNSDevice> _parseMDNSResponse(Uint8List data, String serviceType) {
    final devices = <MDNSDevice>[];
    try {
      if (data.length < 12) return devices;

      final flags = _readUint16(data, 2);
      final isResponse = (flags & 0x8000) != 0;
      if (!isResponse) return devices;

      final answerCount = _readUint16(data, 6);
      final additionalCount = _readUint16(data, 10);

      var offset = 12;
      final questionCount = _readUint16(data, 4);
      for (var i = 0; i < questionCount && offset < data.length; i++) {
        offset = _skipName(data, offset);
        offset += 4;
      }

      final records = <_DNSRecord>[];

      for (var i = 0; i < answerCount + additionalCount && offset < data.length; i++) {
        final record = _parseRecord(data, offset);
        if (record == null) break;
        records.add(record);
        offset = record.endOffset;
      }

      String? serviceName;
      String? hostName;
      int port = 0;
      String? sn;

      for (final record in records) {
        if (record.type == 12) {
          serviceName = record.name;
        } else if (record.type == 1) {
          hostName = record.data;
        } else if (record.type == 33) {
          port = record.port ?? 0;
        } else if (record.type == 16) {
          sn = _parseSNFromTxt(record.txtData);
        }
      }

      if (serviceName != null || hostName != null) {
        devices.add(MDNSDevice(
          name: serviceName ?? hostName ?? 'unknown',
          host: hostName ?? '',
          port: port,
          sn: sn,
        ));
      }
    } catch (_) {}

    return devices;
  }

  String? _parseSNFromTxt(List<int>? txtData) {
    if (txtData == null) return null;
    try {
      final str = String.fromCharCodes(txtData);
      final parts = str.split('\x00');
      for (final part in parts) {
        if (part.startsWith('sn=')) {
          return part.substring(3);
        }
      }
      for (final part in parts) {
        final kv = part.split('=');
        if (kv.length == 2 && kv[0].toLowerCase() == 'sn') {
          return kv[1];
        }
      }
    } catch (_) {}
    return null;
  }

  int _readUint16(Uint8List data, int offset) {
    return (data[offset] << 8) | data[offset + 1];
  }

  int _skipName(Uint8List data, int offset) {
    while (offset < data.length) {
      final len = data[offset];
      if (len == 0) {
        offset++;
        break;
      }
      if ((len & 0xC0) == 0xC0) {
        offset += 2;
        break;
      }
      offset += len + 1;
    }
    return offset;
  }

  _DNSRecord? _parseRecord(Uint8List data, int offset) {
    try {
      offset = _skipName(data, offset);
      if (offset + 10 > data.length) return null;

      final type = _readUint16(data, offset);
      offset += 2;
      offset += 2;
      final ttl = _readUint16(data, offset) << 16 | _readUint16(data, offset + 2);
      offset += 4;
      final rdLength = _readUint16(data, offset);
      offset += 2;

      if (offset + rdLength > data.length) return null;

      String? recordData;
      int? port;
      List<int>? txtData;

      if (type == 1) {
        if (rdLength == 4) {
          recordData = '${data[offset]}.${data[offset + 1]}.${data[offset + 2]}.${data[offset + 3]}';
        }
      } else if (type == 33) {
        if (rdLength >= 6) {
          port = _readUint16(data, offset + 4);
        }
      } else if (type == 16) {
        txtData = data.sublist(offset, offset + rdLength);
      } else if (type == 12) {
        final ptrOffset = offset;
        if ((data[ptrOffset] & 0xC0) == 0xC0) {
          final ptr = ((data[ptrOffset] & 0x3F) << 8) | data[ptrOffset + 1];
          final sb = StringBuffer();
          var p = ptr;
          while (p < data.length && data[p] != 0) {
            final l = data[p];
            if ((l & 0xC0) == 0xC0) break;
            p++;
            if (p + l <= data.length) {
              sb.write(String.fromCharCodes(data.sublist(p, p + l)));
              sb.write('.');
              p += l;
            } else {
              break;
            }
          }
          recordData = sb.toString();
          if (recordData.endsWith('.')) {
            recordData = recordData.substring(0, recordData.length - 1);
          }
        }
      }

      return _DNSRecord(
        name: '',
        type: type,
        ttl: ttl,
        data: recordData,
        port: port,
        txtData: txtData,
        endOffset: offset + rdLength,
      );
    } catch (_) {
      return null;
    }
  }
}

class _DNSRecord {
  final String name;
  final int type;
  final int ttl;
  final String? data;
  final int? port;
  final List<int>? txtData;
  final int endOffset;

  _DNSRecord({
    required this.name,
    required this.type,
    required this.ttl,
    this.data,
    this.port,
    this.txtData,
    required this.endOffset,
  });
}
