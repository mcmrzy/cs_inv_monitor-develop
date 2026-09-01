import 'package:flutter/material.dart';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:go_router/go_router.dart';

import 'package:inv_app/l10n/app_localizations.dart';

import 'package:inv_app/features/auth/presentation/pages/splash_page.dart';

import 'package:inv_app/features/auth/presentation/pages/auth_page.dart';

import 'package:inv_app/features/auth/presentation/pages/jverify_auth_page.dart';

import 'package:inv_app/features/auth/presentation/pages/forgot_password_page.dart';

import 'package:inv_app/features/onboarding/presentation/pages/onboarding_page.dart';

import 'package:inv_app/features/onboarding/presentation/pages/setup_guide_page.dart';

import 'package:inv_app/features/station/presentation/pages/home_page.dart';

import 'package:inv_app/features/station/presentation/pages/station_detail_page.dart';

import 'package:inv_app/features/station/presentation/pages/create_station_page.dart';

import 'package:inv_app/features/station/presentation/pages/edit_station_page.dart';

import 'package:inv_app/features/device/presentation/pages/device_realtime_page.dart';

import 'package:inv_app/features/device/presentation/pages/device_op_logs_page.dart';

import 'package:inv_app/features/device/presentation/pages/device_qr_bind_page.dart';

import 'package:inv_app/features/device_protocol/presentation/pages/device_protocol_page.dart';

import 'package:inv_app/features/device/presentation/pages/wifi_config_page.dart';

import 'package:inv_app/features/device/presentation/pages/add_device_page.dart';

import 'package:inv_app/features/dashboard/presentation/pages/dashboard_overview_page.dart';

import 'package:inv_app/features/alarm/presentation/pages/alarm_detail_page.dart';

import 'package:inv_app/features/notification/presentation/pages/notification_center_page.dart';

import 'package:inv_app/features/profile/presentation/pages/profile_page.dart';

import 'package:inv_app/features/profile/presentation/pages/settings_page.dart';

import 'package:inv_app/features/profile/presentation/pages/edit_profile_page.dart';

import 'package:inv_app/features/profile/presentation/pages/about_page.dart';

import 'package:inv_app/features/profile/presentation/pages/help_center_page.dart';

import 'package:inv_app/features/profile/presentation/pages/operation_history_page.dart';

import 'package:inv_app/features/profile/presentation/pages/offline_mode_settings_page.dart';

import 'package:inv_app/features/profile/presentation/pages/notify_settings_page.dart';

import 'package:inv_app/features/device/presentation/pages/device_edit_page.dart';

import 'package:inv_app/features/device/presentation/pages/history_chart_page.dart';

import 'package:inv_app/features/device/presentation/pages/local_mode_page.dart';

import 'package:inv_app/features/ota/presentation/pages/ota_page.dart';

import 'package:inv_app/features/ota/presentation/pages/ota_detail_page.dart';

import 'package:inv_app/features/ota/presentation/pages/local_ota_page.dart';

import 'package:inv_app/features/ota/domain/entities/local_channel.dart';

import 'package:inv_app/features/ota/presentation/pages/ota_tab_page.dart';

import 'package:inv_app/features/ota/presentation/pages/local_upgrade_page.dart';

import 'package:inv_app/features/ota/presentation/pages/upgrade_history_page.dart';

import 'package:inv_app/features/ota/presentation/pages/firmware_list_page.dart';

import 'package:inv_app/features/ota/presentation/pages/ota_check_all_page.dart';

import 'package:inv_app/features/ota/presentation/pages/firmware_library_page.dart';

import 'package:inv_app/features/ota/presentation/bloc/ota_bloc.dart';

import 'package:inv_app/core/router/guards/auth_guard.dart';

import 'package:inv_app/core/router/route_parameter_parser.dart';

// 主框架/导航/设备列表等组件已拆分至 shell/ 目录，路由文件仅保留路由表
import 'package:inv_app/core/router/shell/main_shell.dart';
import 'package:inv_app/core/router/shell/device_list_page.dart';

import 'package:inv_app/core/services/service_locator.dart';

CustomTransitionPage<void> _slidePage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 250),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final tween = Tween(begin: const Offset(0.06, 0), end: Offset.zero)
          .chain(CurveTween(curve: Curves.easeOutCubic));

      return SlideTransition(
        position: animation.drive(tween),
        child: FadeTransition(opacity: animation, child: child),
      );
    },
  );
}

CustomTransitionPage<void> _fadePage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 250),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(opacity: animation, child: child);
    },
  );
}

CustomTransitionPage<void> _invalidRouteParameterPage(
  GoRouterState state,
  String parameterName,
) {
  return _fadePage(
    state,
    Scaffold(
      body: Center(
        child: Text(
          invalidPositiveRouteParameterMessage(parameterName),
          textAlign: TextAlign.center,
        ),
      ),
    ),
  );
}

class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: '/splash',
    routes: [
      GoRoute(
        path: '/splash',
        name: 'splash',
        pageBuilder: (context, state) => _fadePage(state, const SplashPage()),
      ),
      GoRoute(
        path: '/onboarding',
        name: 'onboarding',
        pageBuilder: (context, state) =>
            _fadePage(state, const OnboardingPage()),
      ),
      GoRoute(
        path: '/setup-guide',
        name: 'setupGuide',
        pageBuilder: (context, state) =>
            _slidePage(state, const SetupGuidePage()),
      ),
      GoRoute(
        path: '/login',
        name: 'login',
        pageBuilder: (context, state) =>
            _fadePage(state, const AuthPage(initialMode: AuthMode.login)),
      ),
      GoRoute(
        path: '/jverify-login',
        name: 'jverifyAuth',
        pageBuilder: (context, state) =>
            _fadePage(state, const JVerifyAuthPage()),
      ),
      GoRoute(
        path: '/register',
        name: 'register',
        pageBuilder: (context, state) =>
            _fadePage(state, const AuthPage(initialMode: AuthMode.register)),
      ),
      GoRoute(
        path: '/forgot-password',
        name: 'forgotPassword',
        pageBuilder: (context, state) =>
            _slidePage(state, const ForgotPasswordPage()),
      ),
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/home',
            name: 'home',
            builder: (context, state) => const HomePage(),
          ),
          GoRoute(
            path: '/statistics',
            name: 'statistics',
            builder: (context, state) => const DashboardOverviewPage(),
          ),
          GoRoute(
            path: '/alarms',
            name: 'alarms',
            builder: (context, state) => const NotificationCenterPage(),
          ),
          GoRoute(
            path: '/devices',
            name: 'devices',
            builder: (context, state) => const DeviceListPage(),
          ),
          GoRoute(
            path: '/profile',
            name: 'profile',
            builder: (context, state) => const ProfilePage(),
          ),
        ],
      ),
      GoRoute(
        path: '/ota',
        name: 'otaTab',
        pageBuilder: (context, state) => _slidePage(state, const OtaTabPage()),
      ),
      GoRoute(
        path: '/station/create',
        name: 'createStation',
        pageBuilder: (context, state) =>
            _slidePage(state, const CreateStationPage()),
      ),
      GoRoute(
        path: '/station/:id',
        name: 'stationDetail',
        pageBuilder: (context, state) {
          final id = parsePositiveRouteInt(state.pathParameters['id']);
          if (id == null) {
            return _invalidRouteParameterPage(state, 'id');
          }
          // 支持 ?tab=devices 直达设备管理 Tab（首页“移除设备”入口）
          final initialTab =
              state.uri.queryParameters['tab'] == 'devices' ? 2 : 0;

          return _slidePage(
            state,
            StationDetailPage(stationId: id, initialTab: initialTab),
          );
        },
      ),
      GoRoute(
        path: '/station/:id/edit',
        name: 'editStation',
        pageBuilder: (context, state) {
          final id = parsePositiveRouteInt(state.pathParameters['id']);
          if (id == null) {
            return _invalidRouteParameterPage(state, 'id');
          }

          return _slidePage(state, EditStationPage(stationId: id));
        },
      ),
      // 扫码绑定页：必须声明在 /device/:sn 之前，
      // go_router 按声明顺序匹配，否则 qr-bind 会被 :sn 吞掉
      GoRoute(
        path: '/device/qr-bind',
        name: 'deviceQrBind',
        pageBuilder: (context, state) => _slidePage(
          state,
          DeviceQrBindPage(
            sn: state.uri.queryParameters['sn'] ?? '',
            pin: state.uri.queryParameters['pin'] ?? '',
            stationId: parsePositiveRouteInt(
              state.uri.queryParameters['station_id'],
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/device/:sn',
        name: 'deviceRealtime',
        pageBuilder: (context, state) {
          final sn = state.pathParameters['sn']!;

          return _slidePage(state, DeviceRealtimePage(sn: sn, type: 'inv'));
        },
      ),
      GoRoute(
        path: '/device/:sn/control',
        name: 'deviceControl',
        pageBuilder: (context, state) {
          final sn = state.pathParameters['sn']!;

          return _slidePage(state, DeviceControlPageWrapper(deviceSN: sn));
        },
      ),
      GoRoute(
        path: '/device/:sn/protocol',
        name: 'deviceProtocol',
        pageBuilder: (context, state) {
          final sn = state.pathParameters['sn']!;

          return _slidePage(state, DeviceProtocolPage(sn: sn));
        },
      ),
      GoRoute(
        path: '/device/:sn/history',
        name: 'deviceHistory',
        pageBuilder: (context, state) {
          final sn = state.pathParameters['sn']!;

          return _slidePage(state, HistoryChartPage(deviceSN: sn));
        },
      ),
      GoRoute(
        path: '/device/op-logs/:sn',
        name: 'deviceOpLogs',
        pageBuilder: (context, state) => _slidePage(
          state,
          DeviceOpLogsPage(sn: state.pathParameters['sn']!),
        ),
      ),
      GoRoute(
        path: '/device/:sn/edit',
        name: 'deviceEdit',
        pageBuilder: (context, state) {
          final sn = state.pathParameters['sn']!;
          // extra 传设备快照与电站上下文；深链接无 extra 时回退最小快照
          final extra = state.extra as Map<String, dynamic>?;
          final device =
              (extra?['device'] as Map?)?.cast<String, dynamic>() ??
                  <String, dynamic>{'sn': sn};
          final stationId = extra?['stationId'] as int?;
          final onEnterSortMode = extra?['onEnterSortMode'] as void Function()?;

          return _slidePage(
            state,
            DeviceEditPage(
              sn: sn,
              device: device,
              stationId: stationId,
              onEnterSortMode: onEnterSortMode,
            ),
          );
        },
      ),
      GoRoute(
        path: '/wifi-config',
        name: 'wifiConfig',
        pageBuilder: (context, state) =>
            _slidePage(state, const WifiConfigPage()),
      ),
      GoRoute(
        path: '/local-mode',
        name: 'localMode',
        pageBuilder: (context, state) =>
            _slidePage(state, const LocalModePage()),
      ),
      GoRoute(
        path: '/local-ota',
        name: 'localOta',
        pageBuilder: (context, state) {
          final sn = state.uri.queryParameters['sn'] ?? '';
          final ip = state.uri.queryParameters['ip'] ?? '';
          return _slidePage(
            state,
            LocalOTAPage(deviceSN: sn, deviceIP: ip),
          );
        },
      ),
      GoRoute(
        path: '/add-device',
        name: 'addDevice',
        pageBuilder: (context, state) {
          return _slidePage(
            state,
            AddDevicePage(
              stationId: parsePositiveRouteInt(
                state.uri.queryParameters['station_id'],
              ),
            ),
          );
        },
      ),
      GoRoute(
        path: '/alarm/:id',
        name: 'alarmDetail',
        pageBuilder: (context, state) {
          final id = parsePositiveRouteInt(state.pathParameters['id']);
          if (id == null) {
            return _invalidRouteParameterPage(state, 'id');
          }

          return _slidePage(state, AlarmDetailPage(alarmId: id));
        },
      ),
      GoRoute(
        path: '/settings',
        name: 'settings',
        pageBuilder: (context, state) =>
            _slidePage(state, const SettingsPage()),
      ),
      GoRoute(
        path: '/help-center',
        name: 'helpCenter',
        pageBuilder: (context, state) =>
            _slidePage(state, const HelpCenterPage()),
      ),
      GoRoute(
        path: '/operation-history',
        name: 'operationHistory',
        pageBuilder: (context, state) =>
            _slidePage(state, const OperationHistoryPage()),
      ),
      GoRoute(
        path: '/offline-mode-settings',
        name: 'offlineModeSettings',
        pageBuilder: (context, state) =>
            _slidePage(state, const OfflineModeSettingsPage()),
      ),
      GoRoute(
        path: '/edit-profile',
        name: 'editProfile',
        pageBuilder: (context, state) =>
            _slidePage(state, const EditProfilePage()),
      ),
      GoRoute(
        path: '/about',
        name: 'about',
        pageBuilder: (context, state) => _slidePage(state, const AboutPage()),
      ),
      GoRoute(
        path: '/notify-settings',
        name: 'notifySettings',
        pageBuilder: (context, state) =>
            _slidePage(state, const NotifySettingsPage()),
      ),
      // 检查更新（全部设备）：必须声明在 /ota/:sn 之前，
      // 避免 check-all 被 :sn 参数捕获
      GoRoute(
        path: '/ota/check-all',
        name: 'otaCheckAll',
        pageBuilder: (context, state) =>
            _slidePage(state, const OtaCheckAllPage()),
      ),
      GoRoute(
        path: '/ota/:sn',
        name: 'ota',
        pageBuilder: (context, state) {
          final sn = state.pathParameters['sn']!;

          return _slidePage(
            state,
            BlocProvider(
              create: (_) => getIt<OtaBloc>(),
              child: OTAPage(deviceSN: sn),
            ),
          );
        },
      ),
      GoRoute(
        path: '/ota/:sn/detail',
        name: 'otaDetail',
        pageBuilder: (context, state) {
          final sn = state.pathParameters['sn']!;

          final taskId = parseNonNegativeRouteInt(
            state.uri.queryParameters['task_id'],
          );

          return _slidePage(
            state,
            BlocProvider(
              create: (_) => getIt<OtaBloc>(),
              child: OTADetailPage(deviceSN: sn, taskId: taskId),
            ),
          );
        },
      ),
      GoRoute(
        path: '/ota/:sn/local',
        name: 'otaLocal',
        pageBuilder: (context, state) {
          final sn = state.pathParameters['sn']!;

          final deviceIP = state.uri.queryParameters['ip'] ?? '192.168.4.1';

          final firmwareId = state.uri.queryParameters['firmware_id'] != null
              ? int.tryParse(state.uri.queryParameters['firmware_id']!)
              : null;

          final firmwareUrl = state.uri.queryParameters['firmware_url'];

          final firmwareFileName =
              state.uri.queryParameters['firmware_file_name'];

          final targetChip = state.uri.queryParameters['target_chip'];
          final firmwareVersion = state.uri.queryParameters['firmware_version'];
          final fileSha256 = state.uri.queryParameters['file_sha256'];
          final securityVersion =
              int.tryParse(state.uri.queryParameters['security_version'] ?? '');
          final releaseSignature =
              state.uri.queryParameters['release_signature'];

          // 通信通道：channel=ble 走蓝牙，缺省 WiFi 热点（本地升级双 Tab 页传入）
          final channel = state.uri.queryParameters['channel'] == 'ble'
              ? LocalCommunicationChannel.ble
              : LocalCommunicationChannel.wifiAp;

          return _slidePage(
            state,
            LocalOTAPage(
              deviceSN: sn,
              deviceIP: deviceIP,
              channel: channel,
              firmwareId: firmwareId,
              firmwareUrl: firmwareUrl,
              firmwareFileName: firmwareFileName,
              targetChip: targetChip,
              firmwareVersion: firmwareVersion,
              fileSha256: fileSha256,
              securityVersion: securityVersion,
              releaseSignature: releaseSignature,
            ),
          );
        },
      ),
      // 本地升级双 Tab 页（BLE 直连 / WiFi 热点）——需求 16
      GoRoute(
        path: '/local-upgrade',
        name: 'localUpgrade',
        pageBuilder: (context, state) {
          final sn = state.uri.queryParameters['sn'] ?? '';
          final model = state.uri.queryParameters['model'] ?? '';
          return _slidePage(
            state,
            LocalUpgradePage(deviceSN: sn, deviceModel: model),
          );
        },
      ),
      // 设备升级历史（含回退权限门控）——需求 16
      GoRoute(
        path: '/upgrade-history',
        name: 'upgradeHistory',
        pageBuilder: (context, state) {
          final sn = state.uri.queryParameters['sn'] ?? '';
          return _slidePage(
            state,
            UpgradeHistoryPage(deviceSN: sn),
          );
        },
      ),
      // 固件列表（按设备过滤）——需求 16
      GoRoute(
        path: '/firmware-list',
        name: 'firmwareList',
        pageBuilder: (context, state) {
          final sn = state.uri.queryParameters['sn'] ?? '';
          final model = state.uri.queryParameters['model'] ?? '';
          final version = state.uri.queryParameters['version'] ?? '';
          return _slidePage(
            state,
            BlocProvider(
              create: (_) => getIt<OtaBloc>(),
              child: FirmwareListPage(
                sn: sn,
                deviceModel: model,
                currentMainVersion: version,
              ),
            ),
          );
        },
      ),
      // 固件库（按型号浏览发布版本，可预下载到本地）
      GoRoute(
        path: '/firmware-library',
        name: 'firmwareLibrary',
        pageBuilder: (context, state) {
          final model = state.uri.queryParameters['model'];
          return _slidePage(
            state,
            FirmwareLibraryPage(initialModel: model),
          );
        },
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text(
          '${AppLocalizations.of(context)!.pageNotFound}: ${state.error}',
        ),
      ),
    ),
    redirect: (context, state) async {
      return await AuthGuard.redirect(context, state);
    },
  );
}
