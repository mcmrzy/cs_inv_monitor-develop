import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:inv_app/core/services/connection_mode_service.dart';
import 'package:inv_app/core/services/service_locator.dart';

import '../../helpers/mock_providers.dart';

void main() {
  late ConnectionModeService connectionModeService;
  late MockStorageService mockStorageService;
  late MockMQTTService mockMQTTService;

  setUp(() {
    mockStorageService = MockStorageService();
    mockMQTTService = MockMQTTService();

    // Register MQTTService mock with getIt for switchToRemote
    getIt.registerFactory(() => mockMQTTService);

    connectionModeService = ConnectionModeService(mockStorageService);
  });

  tearDown(() {
    connectionModeService.dispose();
    getIt.reset();
  });

  // ---------------------------------------------------------------------------
  // Initial state
  // ---------------------------------------------------------------------------
  group('initial state', () {
    test('defaults to remote mode', () {
      expect(connectionModeService.currentMode, ConnectionMode.remote);
      expect(connectionModeService.isLocal, false);
      expect(connectionModeService.isRemote, true);
    });
  });

  // ---------------------------------------------------------------------------
  // init
  // ---------------------------------------------------------------------------
  group('init', () {
    test('sets local mode when storage returns true', () async {
      when(() => mockStorageService.getIsLocalMode())
          .thenAnswer((_) async => true);

      await connectionModeService.init();

      expect(connectionModeService.currentMode, ConnectionMode.local);
      expect(connectionModeService.isLocal, true);
    });

    test('sets remote mode when storage returns false', () async {
      when(() => mockStorageService.getIsLocalMode())
          .thenAnswer((_) async => false);

      await connectionModeService.init();

      expect(connectionModeService.currentMode, ConnectionMode.remote);
      expect(connectionModeService.isRemote, true);
    });

    test('emits mode to stream on init', () async {
      when(() => mockStorageService.getIsLocalMode())
          .thenAnswer((_) async => true);

      final completer = Completer<ConnectionMode>();
      final sub = connectionModeService.modeStream.listen((mode) {
        if (!completer.isCompleted) completer.complete(mode);
      });

      await connectionModeService.init();

      final emitted = await completer.future.timeout(
        const Duration(seconds: 1),
      );
      expect(emitted, ConnectionMode.local);

      await sub.cancel();
    });
  });

  // ---------------------------------------------------------------------------
  // setLocalMode
  // ---------------------------------------------------------------------------
  group('setLocalMode', () {
    test('switches to local mode and saves to storage', () async {
      when(() => mockStorageService.saveIsLocalMode(any()))
          .thenAnswer((_) async {});

      await connectionModeService.setLocalMode(true);

      expect(connectionModeService.currentMode, ConnectionMode.local);
      verify(() => mockStorageService.saveIsLocalMode(true)).called(1);
    });

    test('switches to remote mode and saves to storage', () async {
      when(() => mockStorageService.saveIsLocalMode(any()))
          .thenAnswer((_) async {});

      await connectionModeService.setLocalMode(false);

      expect(connectionModeService.currentMode, ConnectionMode.remote);
      verify(() => mockStorageService.saveIsLocalMode(false)).called(1);
    });

    test('emits mode change to stream', () async {
      when(() => mockStorageService.saveIsLocalMode(any()))
          .thenAnswer((_) async {});

      final completer = Completer<ConnectionMode>();
      final sub = connectionModeService.modeStream.listen((mode) {
        if (!completer.isCompleted) completer.complete(mode);
      });

      await connectionModeService.setLocalMode(true);

      final emitted = await completer.future.timeout(
        const Duration(seconds: 1),
      );
      expect(emitted, ConnectionMode.local);

      await sub.cancel();
    });
  });

  // ---------------------------------------------------------------------------
  // isLocalMode
  // ---------------------------------------------------------------------------
  group('isLocalMode', () {
    test('returns value from storage', () async {
      when(() => mockStorageService.getIsLocalMode())
          .thenAnswer((_) async => true);

      final result = await connectionModeService.isLocalMode();
      expect(result, true);
    });

    test('returns false when storage returns false', () async {
      when(() => mockStorageService.getIsLocalMode())
          .thenAnswer((_) async => false);

      final result = await connectionModeService.isLocalMode();
      expect(result, false);
    });
  });

  // ---------------------------------------------------------------------------
  // switchToLocal
  // ---------------------------------------------------------------------------
  group('switchToLocal', () {
    test('switches to local mode and saves', () async {
      when(() => mockStorageService.saveIsLocalMode(any()))
          .thenAnswer((_) async {});

      await connectionModeService.switchToLocal();

      expect(connectionModeService.currentMode, ConnectionMode.local);
      expect(connectionModeService.isLocal, true);
      verify(() => mockStorageService.saveIsLocalMode(true)).called(1);
    });
  });

  // ---------------------------------------------------------------------------
  // switchToRemote
  // ---------------------------------------------------------------------------
  group('switchToRemote', () {
    test('switches to remote mode and saves', () async {
      when(() => mockStorageService.saveIsLocalMode(any()))
          .thenAnswer((_) async {});
      when(() => mockMQTTService.isConnected).thenReturn(true);

      await connectionModeService.switchToRemote();

      expect(connectionModeService.currentMode, ConnectionMode.remote);
      expect(connectionModeService.isRemote, true);
      verify(() => mockStorageService.saveIsLocalMode(false)).called(1);
    });

    test('reconnects MQTT when not connected', () async {
      when(() => mockStorageService.saveIsLocalMode(any()))
          .thenAnswer((_) async {});
      when(() => mockMQTTService.isConnected).thenReturn(false);
      when(() => mockMQTTService.reconnect()).thenAnswer((_) async {});

      await connectionModeService.switchToRemote();

      verify(() => mockMQTTService.reconnect()).called(1);
    });

    test('does not reconnect MQTT when already connected', () async {
      when(() => mockStorageService.saveIsLocalMode(any()))
          .thenAnswer((_) async {});
      when(() => mockMQTTService.isConnected).thenReturn(true);

      await connectionModeService.switchToRemote();

      verifyNever(() => mockMQTTService.reconnect());
    });
  });

  // ---------------------------------------------------------------------------
  // modeStream
  // ---------------------------------------------------------------------------
  group('modeStream', () {
    test('is a broadcast stream', () {
      expect(connectionModeService.modeStream.isBroadcast, true);
    });
  });
}
