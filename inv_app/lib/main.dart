import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/config/app_config.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/locale_service.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:inv_app/features/station/presentation/bloc/station_bloc.dart';
import 'package:inv_app/features/device/presentation/bloc/device_bloc.dart';
import 'package:inv_app/features/alarm/presentation/bloc/alarm_bloc.dart';
import 'package:inv_app/features/notification/presentation/bloc/notification_bloc.dart';
import 'package:inv_app/features/dashboard/presentation/bloc/dashboard_bloc.dart';
import 'package:inv_app/core/router/app_router.dart';
import 'package:inv_app/l10n/app_localizations.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await ServiceLocator.init();

  runApp(const InvApp());
}

class InvApp extends StatefulWidget {
  const InvApp({super.key});

  @override
  State<InvApp> createState() => _InvAppState();
}

class _InvAppState extends State<InvApp> {
  Locale _currentLocale = const Locale('zh', 'CN');

  @override
  void initState() {
    super.initState();
    _currentLocale = getIt<LocaleService>().currentLocale;
    getIt<LocaleService>().localeStream.listen((locale) {
      if (mounted) {
        setState(() {
          _currentLocale = locale;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<AuthBloc>(
          create: (_) => getIt<AuthBloc>()..add(AuthCheckRequested()),
        ),
        BlocProvider<StationBloc>(
          create: (_) => getIt<StationBloc>(),
        ),
        BlocProvider<DeviceBloc>(
          create: (_) => getIt<DeviceBloc>(),
        ),
        BlocProvider<AlarmBloc>(
          create: (_) => getIt<AlarmBloc>(),
        ),
        BlocProvider<NotificationBloc>(
          create: (_) => getIt<NotificationBloc>(),
        ),
        BlocProvider<DashboardBloc>(
          create: (_) => getIt<DashboardBloc>(),
        ),
      ],
      child: ScreenUtilInit(
        designSize: const Size(375, 812),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (context, child) {
          return MaterialApp.router(
            title: AppConfig.appName,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: ThemeMode.system,
            routerConfig: AppRouter.router,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            locale: _currentLocale,
            builder: (context, widget) {
              return MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(1.0),
                ),
                child: widget!,
              );
            },
          );
        },
      ),
    );
  }
}
