import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:inv_app/core/services/connection_mode_service.dart';
import 'package:inv_app/core/services/service_locator.dart';

import '../../helpers/mock_providers.dart';

void main() {
  late ConnectionModeService connectionModeService;
  late MockStorageService mockStorageService;
  late MockNetworkStatusService mockNetworkStatusService;
  late StreamController<bool> networkController;

  setUp(() {
    mockStorageService = MockStorageService();
    mockNetworkStatusService = MockNetworkStatusService();
    networkController = StreamController<bool>.broadcast();

    when(() => mockStorageService.getIsLocalMode())
        .thenAnswer((_) async => false);
    when(() => mockStorageService.getIsGuestLocalMode())
        .thenAnswer((_) async => false);
    when(() => mockStorageService.saveIsLocalMode(any()))
        .thenAnswer((_) async {});
    when(() => mockStorageService.saveIsGuestLocalMode(any()))
        .thenAnswer((_) async {});
    when(() => mockNetworkStatusService.statusStream)
        .thenAnswer((_) => networkController.stream);

    connectionModeService = ConnectionModeService(
      mockStorageService,
      networkStatusService: mockNetworkStatusService,
    );
  });

  tearDown(() {
    connectionModeService.dispose();
    networkController.close();
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

      await connectionModeService.switchToRemote();

      expect(connectionModeService.currentMode, ConnectionMode.remote);
      expect(connectionModeService.isRemote, true);
      verify(() => mockStorageService.saveIsLocalMode(false)).called(1);
    });
  });

  // ---------------------------------------------------------------------------
  // enterGuestLocalMode / exitGuestLocalMode (Q4)
  // ---------------------------------------------------------------------------
  group('guest local mode', () {
    test('enterGuestLocalMode sets guest flag and switches to local',
        () async {
      await connectionModeService.enterGuestLocalMode();

      expect(connectionModeService.isGuestLocalMode, true);
      expect(connectionModeService.currentMode, ConnectionMode.local);
      verify(() => mockStorageService.saveIsGuestLocalMode(true)).called(1);
      verify(() => mockStorageService.saveIsLocalMode(true)).called(1);
    });

    test('exitGuestLocalMode clears guest flag', () async {
      await connectionModeService.enterGuestLocalMode();

      await connectionModeService.exitGuestLocalMode();

      expect(connectionModeService.isGuestLocalMode, false);
      verify(() => mockStorageService.saveIsGuestLocalMode(false)).called(1);
    });
  });

  // ---------------------------------------------------------------------------
  // Network-driven auto switch (Q7)
  // ---------------------------------------------------------------------------
  group('auto switch on network status', () {
    test('init restores guest flag from storage', () async {
      when(() => mockStorageService.getIsGuestLocalMode())
          .thenAnswer((_) async => true);

      await connectionModeService.init();

      expect(connectionModeService.isGuestLocalMode, true);
    });

    test('switches to local when network goes offline (confirmed)', () async {
      when(() => mockStorageService.getIsLocalMode())
          .thenAnswer((_) async => false);

      await connectionModeService.init();
      expect(connectionModeService.currentMode, ConnectionMode.remote);

      // NetworkStatusService 连续确认离线后广播 false（阈值在其内部实现）
      networkController.add(false);
      await Future<void>.delayed(Duration.zero);

      expect(connectionModeService.currentMode, ConnectionMode.local);
      verify(() => mockStorageService.saveIsLocalMode(true)).called(1);
    });

    test('switches back to remote when network recovers', () async {
      when(() => mockStorageService.getIsLocalMode())
          .thenAnswer((_) async => true);

      await connectionModeService.init();
      expect(connectionModeService.currentMode, ConnectionMode.local);

      networkController.add(true);
      await Future<void>.delayed(Duration.zero);

      expect(connectionModeService.currentMode, ConnectionMode.remote);
      verify(() => mockStorageService.saveIsLocalMode(false)).called(1);
    });

    test('manual override wins over network events', () async {
      when(() => mockStorageService.getIsLocalMode())
          .thenAnswer((_) async => false);

      await connectionModeService.init();
      await connectionModeService.switchToLocal(); // 用户手动选择本地

      networkController.add(true); // 网络恢复，不应自动切回云端
      await Future<void>.delayed(Duration.zero);

      expect(connectionModeService.currentMode, ConnectionMode.local);
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
