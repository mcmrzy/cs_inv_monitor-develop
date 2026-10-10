import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fpdart/fpdart.dart' hide State;
import 'package:mocktail/mocktail.dart';
import 'package:inv_app/core/errors/failures.dart';
import 'package:inv_app/core/services/storage_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/ble/ble_adapter.dart';
import 'package:inv_app/core/services/ble/ble_direct_service.dart';
import 'package:inv_app/features/device/presentation/pages/add_device_page.dart';
import 'package:inv_app/features/device/presentation/bloc/device_bloc.dart';
import 'package:inv_app/features/station/presentation/bloc/station_bloc.dart'
    as station;
import 'package:inv_app/core/utils/sn_utils.dart';
import 'package:inv_app/features/device/presentation/pages/owned_device_selection_service.dart';
import 'package:inv_app/features/device/presentation/widgets/add_device_tabs.dart';
import 'package:inv_app/features/device/presentation/widgets/owned_device_selection.dart';
import 'package:inv_app/features/station/domain/repositories/station_repository.dart';
import 'package:inv_app/features/station/data/repositories/station_repository_impl.dart';
import 'package:inv_app/features/station/data/datasources/station_remote_data_source.dart';
import 'package:inv_app/l10n/app_en.dart';
import 'package:inv_app/l10n/app_localizations.dart';

class MockDio extends Mock implements Dio {}

class MockStorage extends Mock implements StorageService {}

class MockStations extends Mock implements StationRepository {}

class MockSelection extends Mock implements OwnedDeviceSelectionService {}

class MockDeviceBloc extends Mock implements DeviceBloc {}

class MockStationBloc extends Mock implements station.StationBloc {}

class MockBleDirect extends Mock implements BleDirectService {}

class MockBleAdapter extends Mock implements BleAdapter {}

const _strings = en;

class _TestLocalizations extends LocalizationsDelegate<AppLocalizations> {
  const _TestLocalizations();
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture(AppLocalizations(_strings));
  @override
  bool shouldReload(_TestLocalizations old) => false;
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double scale = 1,
}) async {
  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(375, 812),
      minTextAdapt: true,
      builder: (_, __) => MaterialApp(
        localizationsDelegates: const [_TestLocalizations()],
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData.fromView(tester.view).copyWith(
              textScaler: TextScaler.linear(scale),
            ),
            child: child,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Map<String, dynamic> _device(String sn, {int owner = 7, int? station}) => {
      'sn': sn,
      'user_id': owner,
      'station_id': station,
      'alias': 'Roof inverter $sn',
      'station_name': station == null ? '' : 'Roof station',
      'status': 1,
      'location': 'North roof',
    };

Response _response(dynamic data, {int code = 0}) => Response(
      requestOptions: RequestOptions(path: ''),
      statusCode: 200,
      data: {'code': code, 'message': 'permission denied', 'data': data},
    );

void main() {
  group('Real add-device page integration', () {
    late GoRouter router;
    late MockDeviceBloc devices;
    late MockStationBloc stations;
    Uri? verifiedRoute;

    setUp(() async {
      await getIt.reset();
      verifiedRoute = null;
      SharedPreferences.setMockInitialValues({});
      devices = MockDeviceBloc();
      stations = MockStationBloc();
      when(() => devices.state).thenReturn(DeviceInitial());
      when(() => devices.stream).thenAnswer((_) => const Stream.empty());
      when(() => stations.state).thenReturn(station.StationInitial());
      when(() => stations.stream).thenAnswer((_) => const Stream.empty());
      final dio = MockDio();
      when(() => dio.get('/stations/42')).thenAnswer(
        (_) async => _response({
          'station': {'name': 'Selected roof station'},
        }),
      );
      final direct = MockBleDirect();
      when(() => direct.enabled).thenReturn(false);
      final adapter = MockBleAdapter();
      when(() => adapter.status).thenAnswer((_) async => BleAdapterStatus.off);
      getIt.registerSingleton<Dio>(dio);
      getIt.registerSingleton<StorageService>(MockStorage());
      getIt.registerSingleton<StationRepository>(MockStations());
      getIt.registerSingleton<BleDirectService>(direct);
      getIt.registerSingleton<BleAdapter>(adapter);
      router = GoRouter(
        initialLocation: '/add',
        routes: [
          GoRoute(
            path: '/add',
            builder: (_, __) => const AddDevicePage(stationId: 42),
          ),
          GoRoute(
            path: '/device/qr-bind',
            builder: (_, state) {
              verifiedRoute = state.uri;
              return Text('VERIFY ${state.uri.queryParameters}');
            },
          ),
        ],
      );
    });

    tearDown(() async {
      router.dispose();
      await getIt.reset();
    });

    Future<void> pumpPage(WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(375, 812),
          minTextAdapt: true,
          builder: (_, __) => MultiBlocProvider(
            providers: [
              BlocProvider<DeviceBloc>.value(value: devices),
              BlocProvider<station.StationBloc>.value(value: stations),
            ],
            child: MaterialApp.router(
              routerConfig: router,
              localizationsDelegates: const [_TestLocalizations()],
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
        'manual validation and verified route retain selected station on a narrow screen',
        (tester) async {
      await pumpPage(tester);
      await tester.ensureVisible(find.text(en['add_device_manual']!));
      await tester.tap(find.text(en['add_device_manual']!));
      await tester.pumpAndSettle();
      final sn = 'H1CNA001Q100001${calculateCheckDigit('H1CNA001Q100001')}';
      expect(validateSN(sn), isTrue);
      final snField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == en['device_sn_label'],
      );
      final pinField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == en['manual_pin_label'],
      );
      final listScroll = find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      );
      await tester.scrollUntilVisible(snField, 100, scrollable: listScroll);
      await tester.enterText(snField, sn);
      await tester.scrollUntilVisible(pinField, 100, scrollable: listScroll);
      await tester.enterText(pinField, '12345');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      final bind = find.widgetWithText(ElevatedButton, en['bind_device']!);
      await tester.ensureVisible(bind);
      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pumpAndSettle();
      await tester.tap(bind);
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/add');
      expect(find.text(en['pin_length_error']!), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      await tester.ensureVisible(pinField);
      await tester.enterText(pinField, '123456');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.ensureVisible(bind);
      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pumpAndSettle();
      await tester.tap(bind);
      await tester.pumpAndSettle();
      expect(verifiedRoute, isNotNull);
      final uri = verifiedRoute!;
      expect(uri.path, '/device/qr-bind');
      expect(
        uri.queryParameters,
        {'sn': sn, 'pin': '123456', 'station_id': '42'},
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
        'real nearby view remains separate from manual input with large text',
        (tester) async {
      await pumpPage(tester);
      await tester.tap(find.text('Select Device'));
      await tester.pumpAndSettle();
      expect(find.text(en['ble_found_devices']!), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Selected roof station'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('Owned selection uses existing authenticated endpoints', () {
    late MockDio dio;
    late MockStorage storage;
    late MockStations stations;
    late OwnedDeviceSelectionService service;

    setUp(() {
      dio = MockDio();
      storage = MockStorage();
      stations = MockStations();
      when(() => storage.getUserId()).thenAnswer((_) async => 7);
      service = OwnedDeviceSelectionService(
        dio: dio,
        storage: storage,
        stations: stations,
      );
    });

    void listResponse(dynamic data, {int code = 0}) {
      when(
        () => dio.get(
          '/devices',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer((_) async => _response(data, code: code));
    }

    void detailResponse(Map<String, dynamic> device) {
      when(() => dio.get('/devices/by-sn/OWNED'))
          .thenAnswer((_) async => _response({'device': device}));
    }

    test(
        'filters shared, hierarchical, admin-visible and missing owners; sends server pagination and search',
        () async {
      listResponse({
        'items': [
          _device('OWNED'),
          _device('OTHER', owner: 8),
          {'sn': 'UNKNOWN'},
        ],
        'total': 61,
      });
      final page = await service.load(page: 2, keyword: ' Roof ');
      expect(page.items.map((d) => d['sn']), ['OWNED']);
      expect(page.hasMore, isTrue);
      verify(
        () => dio.get(
          '/devices',
          queryParameters: {'page': 2, 'page_size': 20, 'keyword': 'Roof'},
        ),
      ).called(1);
    });

    test('filtered empty page still permits loading later owned devices',
        () async {
      listResponse({
        'items': [_device('SHARED', owner: 8)],
        'total': 21,
      });
      final page = await service.load();
      expect(page.items, isEmpty);
      expect(page.hasMore, isTrue);
    });

    test('explicit owner_user_id takes precedence over a readable user_id',
        () async {
      listResponse({
        'items': [
          {..._device('SHARED'), 'owner_user_id': 8},
          {..._device('OWNED', owner: 8), 'owner_user_id': 7},
          {..._device('MISSING'), 'owner_user_id': null},
        ],
        'total': 3,
      });
      final result = await service.load();
      expect(result.items.map((device) => device['sn']), ['OWNED']);
    });

    test('unauthenticated account never requests device list', () async {
      when(() => storage.getUserId()).thenAnswer((_) async => null);
      await expectLater(service.load(), throwsA(isA<UnauthorizedFailure>()));
      verifyZeroInteractions(dio);
    });

    test('malformed and business failure pages remain errors', () async {
      listResponse({'items': null, 'total': 0});
      await expectLater(service.load(), throwsFormatException);
      listResponse({'items': [], 'total': 0}, code: 403);
      await expectLater(service.load(), throwsA(isA<Exception>()));
    });

    test('account change discards in-flight list', () async {
      var reads = 0;
      when(() => storage.getUserId())
          .thenAnswer((_) async => ++reads == 1 ? 7 : 8);
      listResponse({
        'items': [_device('OWNED')],
        'total': 1,
      });
      await expectLater(service.load(), throwsA(isA<UnauthorizedFailure>()));
    });

    test('owned unassigned device associates through station repository',
        () async {
      detailResponse(_device('OWNED'));
      when(() => stations.bindDevice('OWNED', 42))
          .thenAnswer((_) async => const Right(null));
      expect(
        await service.associate('OWNED', 42),
        OwnedDeviceAssociation.added,
      );
      verify(() => stations.bindDevice('OWNED', 42)).called(1);
      verifyNever(() => dio.post(any(), data: any(named: 'data')));
    });

    test(
        'server associate permission denial propagates, without success or rebind fallback',
        () async {
      detailResponse(_device('OWNED'));
      when(() => stations.bindDevice('OWNED', 42)).thenAnswer(
        (_) async => const Left(ForbiddenFailure('station not owned by you')),
      );
      await expectLater(
        service.associate('OWNED', 42),
        throwsA(isA<ForbiddenFailure>()),
      );
      verify(() => stations.bindDevice('OWNED', 42)).called(1);
      verifyNever(() => stations.rebindDevice(any(), any()));
    });

    for (final station in [42, 99]) {
      test(
          'fresh station assignment $station prevents moving or repeated association',
          () async {
        detailResponse(_device('OWNED', station: station));
        expect(
          await service.associate('OWNED', 42),
          OwnedDeviceAssociation.alreadyAssigned,
        );
        verifyZeroInteractions(stations);
      });
    }

    test('read access does not grant write access after owner changes',
        () async {
      detailResponse(_device('OWNED', owner: 8));
      await expectLater(
        service.associate('OWNED', 42),
        throwsA(isA<ForbiddenFailure>()),
      );
      verifyZeroInteractions(stations);
    });

    test('missing assignment does not treat malformed detail as unassigned',
        () async {
      detailResponse(_device('OWNED')..remove('station_id'));
      await expectLater(service.associate('OWNED', 42), throwsFormatException);
      verifyZeroInteractions(stations);
    });

    test('assignment conflict is not retried as an explicit rebind', () async {
      detailResponse(_device('OWNED'));
      final realService = OwnedDeviceSelectionService(
        dio: dio,
        storage: storage,
        stations: StationRepositoryImpl(StationRemoteDataSource(dio)),
      );
      when(() => dio.post('/devices/add-to-station', data: {
            'sn': 'OWNED',
            'station_id': 42,
            'only_unassigned': true,
          })).thenThrow(DioException(
        requestOptions: RequestOptions(path: '/devices/add-to-station'),
        response: Response(
            statusCode: 409,
            requestOptions: RequestOptions(path: '/devices/add-to-station')),
      ));
      await expectLater(realService.associate('OWNED', 42),
          throwsA(isA<ValidationFailure>()));
      verify(() => dio.post('/devices/add-to-station', data: {
            'sn': 'OWNED',
            'station_id': 42,
            'only_unassigned': true,
          })).called(1);
    });

    test('explicit rebind does not send the unassigned guard', () async {
      when(() => dio.post('/devices/add-to-station', data: {
            'sn': 'OWNED',
            'station_id': 42,
          })).thenAnswer((_) async => _response(null));
      await StationRemoteDataSource(dio).rebindDevice('OWNED', 42);
      verify(() => dio.post('/devices/add-to-station', data: {
            'sn': 'OWNED',
            'station_id': 42,
          })).called(1);
    });

    for (final httpDenied in [false, true]) {
      test(
          'existing associate API ${httpDenied ? 'HTTP' : 'business'} denial is preserved end to end',
          () async {
        detailResponse(_device('OWNED'));
        final realStations =
            StationRepositoryImpl(StationRemoteDataSource(dio));
        final realService = OwnedDeviceSelectionService(
          dio: dio,
          storage: storage,
          stations: realStations,
        );
        when(
          () => dio.post(
            '/devices/add-to-station',
            data: {'sn': 'OWNED', 'station_id': 42, 'only_unassigned': true},
          ),
        ).thenAnswer((_) async {
          if (httpDenied) {
            throw DioException(
              requestOptions: RequestOptions(path: '/devices/add-to-station'),
              response: Response(
                statusCode: 403,
                requestOptions: RequestOptions(path: '/devices/add-to-station'),
              ),
            );
          }
          return _response(null, code: 403);
        });
        await expectLater(
          realService.associate('OWNED', 42),
          throwsA(isA<Failure>()),
        );
        verify(
          () => dio.post(
            '/devices/add-to-station',
            data: {'sn': 'OWNED', 'station_id': 42, 'only_unassigned': true},
          ),
        ).called(1);
        verifyNever(() => dio.post('/devices/bind', data: any(named: 'data')));
      });
    }
  });

  group('Selection UI', () {
    late MockSelection service;
    setUp(() {
      service = MockSelection();
      when(
        () => service.load(
          page: any(named: 'page'),
          keyword: any(named: 'keyword'),
        ),
      ).thenAnswer(
        (_) async => OwnedDevicePage(
          [_device('OWNED'), _device('OCCUPIED', station: 99)],
          hasMore: false,
        ),
      );
    });

    Widget selection({
      int? stationId = 42,
      Future<int?> Function()? choose,
      ValueChanged<int>? added,
    }) =>
        OwnedDeviceSelection(
          service: service,
          stationId: stationId,
          selectStation: choose ?? () async => 42,
          onAdded: added ?? (_) {},
        );

    testWidgets(
        '320px large fonts show name SN status location and disable assigned devices',
        (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pump(tester, selection(), scale: 2);
      expect(find.text('Roof inverter OWNED'), findsOneWidget);
      expect(find.text('SN: OWNED'), findsOneWidget);
      expect(find.text('Online'), findsWidgets);
      expect(find.text('North roof'), findsWidgets);
      final occupied = tester
          .widget<IconButton>(find.byKey(const ValueKey('associate-OCCUPIED')));
      expect(occupied.onPressed, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('cancelled station selection never associates', (tester) async {
      await _pump(tester, selection(stationId: null, choose: () async => null));
      await tester.tap(find.byKey(const ValueKey('associate-OWNED')));
      await tester.pumpAndSettle();
      verifyNever(() => service.associate(any(), any()));
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('associate-OWNED')))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets(
        'server rejection keeps selection available and does not report added',
        (tester) async {
      var added = false;
      when(() => service.associate('OWNED', 42))
          .thenThrow(const ForbiddenFailure('permission denied'));
      await _pump(tester, selection(added: (_) => added = true));
      await tester.tap(find.byKey(const ValueKey('associate-OWNED')));
      await tester.pumpAndSettle();
      expect(added, isFalse);
      expect(find.text('Added to station'), findsNothing);
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('associate-OWNED')))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('occupied since listing does not report added', (tester) async {
      var added = false;
      when(() => service.associate('OWNED', 42))
          .thenAnswer((_) async => OwnedDeviceAssociation.alreadyAssigned);
      await _pump(tester, selection(added: (_) => added = true));
      await tester.tap(find.byKey(const ValueKey('associate-OWNED')));
      await tester.pumpAndSettle();
      expect(added, isFalse);
      verify(() => service.load(page: 1, keyword: '')).called(2);
    });

    testWidgets(
        'selected station associates once and refreshes station only on success',
        (tester) async {
      final pending = Completer<OwnedDeviceAssociation>();
      final added = <int>[];
      when(() => service.associate('OWNED', 42))
          .thenAnswer((_) => pending.future);
      await _pump(
        tester,
        selection(stationId: null, choose: () async => 42, added: added.add),
      );
      final button = tester
          .widget<IconButton>(find.byKey(const ValueKey('associate-OWNED')));
      button.onPressed!();
      button.onPressed!();
      await tester.pump();
      pending.complete(OwnedDeviceAssociation.added);
      await tester.pumpAndSettle();
      expect(added, [42]);
      verify(() => service.associate('OWNED', 42)).called(1);
      verify(() => service.load(page: 1, keyword: '')).called(2);
    });

    testWidgets('pagination appends and search resets to first server page',
        (tester) async {
      when(() => service.load(page: 1, keyword: '')).thenAnswer(
        (_) async => OwnedDevicePage([_device('FIRST')], hasMore: true),
      );
      when(() => service.load(page: 2, keyword: '')).thenAnswer(
        (_) async => OwnedDevicePage([_device('SECOND')], hasMore: false),
      );
      when(() => service.load(page: 1, keyword: 'SECOND')).thenAnswer(
        (_) async => OwnedDevicePage([_device('SECOND')], hasMore: false),
      );
      await _pump(tester, selection());
      await tester.tap(find.text('Load More'));
      await tester.pumpAndSettle();
      expect(find.text('SN: FIRST'), findsOneWidget);
      expect(find.text('SN: SECOND'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'SECOND');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(find.text('SN: FIRST'), findsNothing);
      expect(find.text('SN: SECOND'), findsOneWidget);
      verify(() => service.load(page: 1, keyword: 'SECOND')).called(1);
    });

    testWidgets('stale search completion cannot replace a newer query',
        (tester) async {
      final old = Completer<OwnedDevicePage>();
      when(() => service.load(page: 1, keyword: 'OLD'))
          .thenAnswer((_) => old.future);
      when(() => service.load(page: 1, keyword: 'NEW')).thenAnswer(
        (_) async => OwnedDevicePage([_device('NEW')], hasMore: false),
      );
      await _pump(tester, selection());
      await tester.enterText(find.byType(TextField), 'OLD');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.enterText(find.byType(TextField), 'NEW');
      await tester.pump(const Duration(milliseconds: 350));
      old.complete(OwnedDevicePage([_device('OLD')], hasMore: false));
      await tester.pumpAndSettle();
      expect(find.text('SN: NEW'), findsOneWidget);
      expect(find.text('SN: OLD'), findsNothing);
    });

    testWidgets(
        'approved tabs keep station context and separate BLE from manual at 320px',
        (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final visibility = <bool>[];
      var stationSelections = 0;
      await _pump(
        tester,
        AddDeviceTabs(
          stationId: 42,
          stationName: 'Long selected station name for the northern roof',
          onSelectStation: () => stationSelections++,
          onScanVisibilityChanged: visibility.add,
          scan: const Text('SCAN'),
          manual: const Text('MANUAL'),
          nearby: const Text('BLE'),
          owned: const Text('CLOUD'),
        ),
        scale: 2,
      );
      expect(find.text('SCAN'), findsOneWidget);
      await tester.ensureVisible(find.text(en['add_device_manual']!));
      await tester.tap(find.text(en['add_device_manual']!));
      await tester.pumpAndSettle();
      expect(find.text('MANUAL'), findsOneWidget);
      expect(find.text('BLE'), findsNothing);
      await tester.tap(find.text('Select Device'));
      await tester.pumpAndSettle();
      expect(find.text('BLE'), findsOneWidget);
      await tester.ensureVisible(find.text('My Devices'));
      await tester.tap(find.text('My Devices'));
      await tester.pumpAndSettle();
      expect(find.text('CLOUD'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('add-device-station')));
      await tester.pumpAndSettle();
      expect(stationSelections, 1);
      expect(visibility, [false]);
      expect(tester.takeException(), isNull);
    });
  });
}
