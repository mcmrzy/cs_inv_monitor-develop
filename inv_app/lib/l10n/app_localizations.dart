import 'package:flutter/material.dart';
import 'package:inv_app/l10n/app_zh.dart' as zh;
import 'package:inv_app/l10n/app_en.dart' as en;

class AppLocalizations {
  final Map<String, String> _localizedStrings;

  AppLocalizations(this._localizedStrings);

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static const List<Locale> supportedLocales = [
    Locale('zh', 'CN'),
    Locale('en', 'US'),
  ];

  static Map<String, String> _loadStrings(Locale locale) {
    switch (locale.languageCode) {
      case 'zh':
        return zh.zh;
      case 'en':
        return en.en;
      default:
        return zh.zh;
    }
  }

  String get confirm => _localizedStrings['confirm']!;
  String get cancel => _localizedStrings['cancel']!;
  String get save => _localizedStrings['save']!;
  String get delete => _localizedStrings['delete']!;
  String get edit => _localizedStrings['edit']!;
  String get search => _localizedStrings['search']!;
  String get loading => _localizedStrings['loading']!;
  String get retry => _localizedStrings['retry']!;
  String get success => _localizedStrings['success']!;
  String get failure => _localizedStrings['failure']!;
  String get back => _localizedStrings['back']!;
  String get done => _localizedStrings['done']!;
  String get next => _localizedStrings['next']!;
  String get previous => _localizedStrings['previous']!;
  String get login => _localizedStrings['login']!;
  String get register => _localizedStrings['register']!;
  String get forgotPassword => _localizedStrings['forgot_password']!;
  String get phone => _localizedStrings['phone']!;
  String get email => _localizedStrings['email']!;
  String get password => _localizedStrings['password']!;
  String get verifyCode => _localizedStrings['verify_code']!;
  String get rememberPassword => _localizedStrings['remember_password']!;
  String get otherLogin => _localizedStrings['other_login']!;
  String get wechatLogin => _localizedStrings['wechat_login']!;
  String get googleLogin => _localizedStrings['google_login']!;
  String get home => _localizedStrings['home']!;
  String get device => _localizedStrings['device']!;
  String get alarm => _localizedStrings['alarm']!;
  String get statistics => _localizedStrings['statistics']!;
  String get profile => _localizedStrings['profile']!;
  String get station => _localizedStrings['station']!;
  String get settings => _localizedStrings['settings']!;
  String get deviceManagement => _localizedStrings['device_management']!;
  String get deviceDetail => _localizedStrings['device_detail']!;
  String get addDevice => _localizedStrings['add_device']!;
  String get scanCode => _localizedStrings['scan_code']!;
  String get manualInput => _localizedStrings['manual_input']!;
  String get networkConfig => _localizedStrings['network_config']!;
  String get unbindDevice => _localizedStrings['unbind_device']!;
  String get paramSettings => _localizedStrings['param_settings']!;
  String get deviceControl => _localizedStrings['device_control']!;
  String get online => _localizedStrings['online']!;
  String get offline => _localizedStrings['offline']!;
  String get fault => _localizedStrings['fault']!;
  String get realtimeData => _localizedStrings['realtime_data']!;
  String get energyFlow => _localizedStrings['energy_flow']!;
  String get historyChart => _localizedStrings['history_chart']!;
  String get day => _localizedStrings['day']!;
  String get month => _localizedStrings['month']!;
  String get year => _localizedStrings['year']!;
  String get total => _localizedStrings['total']!;
  String get powerGeneration => _localizedStrings['power_generation']!;
  String get chargeAmount => _localizedStrings['charge_amount']!;
  String get dischargeAmount => _localizedStrings['discharge_amount']!;
  String get load => _localizedStrings['load']!;
  String get alarmList => _localizedStrings['alarm_list']!;
  String get alarmDetail => _localizedStrings['alarm_detail']!;
  String get faultDiagnosis => _localizedStrings['fault_diagnosis']!;
  String get contactInstaller => _localizedStrings['contact_installer']!;
  String get contactService => _localizedStrings['contact_service']!;
  String get processed => _localizedStrings['processed']!;
  String get unprocessed => _localizedStrings['unprocessed']!;
  String get severe => _localizedStrings['severe']!;
  String get warning => _localizedStrings['warning']!;
  String get info => _localizedStrings['info']!;
  String get firmwareUpgrade => _localizedStrings['firmware_upgrade']!;
  String get checkUpdate => _localizedStrings['check_update']!;
  String get currentVersion => _localizedStrings['current_version']!;
  String get latestVersion => _localizedStrings['latest_version']!;
  String get downloading => _localizedStrings['downloading']!;
  String get transferring => _localizedStrings['transferring']!;
  String get verifying => _localizedStrings['verifying']!;
  String get upgrading => _localizedStrings['upgrading']!;
  String get upgradeSuccess => _localizedStrings['upgrade_success']!;
  String get upgradeFailed => _localizedStrings['upgrade_failed']!;
  String get preDownload => _localizedStrings['pre_download']!;
  String get localUpgrade => _localizedStrings['local_upgrade']!;
  String get localMode => _localizedStrings['local_mode']!;
  String get remoteMode => _localizedStrings['remote_mode']!;
  String get deviceDiscovery => _localizedStrings['device_discovery']!;
  String get connectDevice => _localizedStrings['connect_device']!;
  String get noInternetHint => _localizedStrings['no_internet_hint']!;
  String get wifiConfig => _localizedStrings['wifi_config']!;
  String get selectWifi => _localizedStrings['select_wifi']!;
  String get inputPassword => _localizedStrings['input_password']!;
  String get configuring => _localizedStrings['configuring']!;
  String get configSuccess => _localizedStrings['config_success']!;
  String get switchWifi => _localizedStrings['switch_wifi']!;
  String get personalCenter => _localizedStrings['personal_center']!;
  String get changePassword => _localizedStrings['change_password']!;
  String get about => _localizedStrings['about']!;
  String get notificationSettings => _localizedStrings['notification_settings']!;
  String get deviceShare => _localizedStrings['device_share']!;
  String get languageSwitch => _localizedStrings['language_switch']!;
  String get darkMode => _localizedStrings['dark_mode']!;
  String get systemSettings => _localizedStrings['system_settings']!;
  String get localModeDesc => _localizedStrings['local_mode_desc']!;
  String get unitSwitch => _localizedStrings['unit_switch']!;
  String get customServer => _localizedStrings['custom_server']!;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return ['zh', 'en'].contains(locale.languageCode);
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    final strings = AppLocalizations._loadStrings(locale);
    return AppLocalizations(strings);
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
