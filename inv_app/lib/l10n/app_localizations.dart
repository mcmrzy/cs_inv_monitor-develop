import 'package:flutter/material.dart';
import 'package:inv_app/l10n/app_zh.dart' as zh;
import 'package:inv_app/l10n/app_en.dart' as en;

class AppLocalizations {
  final Map<String, String> _localizedStrings;

  AppLocalizations(this._localizedStrings);

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  /// 获取字符串，支持参数替换
  /// 用法: l10n.str('time_minutes_ago', {'minutes': '5'}) => '5分钟前'
  String str(String key, [Map<String, String>? params]) {
    var value = _localizedStrings[key] ?? key;
    if (params != null) {
      params.forEach((k, v) {
        value = value.replaceAll('{$k}', v);
      });
    }
    return value;
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

  // 通用操作
  String get confirm => _localizedStrings['confirm']!;
  String get cancel => _localizedStrings['cancel']!;
  String get allDevices => _localizedStrings['all_devices'] ?? 'All';
  String get brandName => _localizedStrings['brand_name'] ?? 'CSERGY';
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
  String get send => _localizedStrings['send']!;
  String get reset => _localizedStrings['reset']!;
  String get noData => _localizedStrings['no_data']!;
  String get unknown => _localizedStrings['unknown']!;

  // 认证
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

  // 导航
  String get home => _localizedStrings['home']!;
  String get device => _localizedStrings['device']!;
  String get alarm => _localizedStrings['alarm']!;
  String get statistics => _localizedStrings['statistics']!;
  String get profile => _localizedStrings['profile']!;
  String get station => _localizedStrings['station']!;
  String get settings => _localizedStrings['settings']!;

  // 电站
  String get stationOverview => _localizedStrings['station_overview']!;
  String get stationStatistics => _localizedStrings['station_statistics']!;
  String get stationDevices => _localizedStrings['station_devices']!;
  String get noStations => _localizedStrings['no_stations']!;
  String get createStation => _localizedStrings['create_station']!;
  String get searchStation => _localizedStrings['search_station']!;
  String get pv => _localizedStrings['pv']!;
  String get battery => _localizedStrings['battery']!;
  String get grid => _localizedStrings['grid']!;
  String get currentPower => _localizedStrings['current_power']!;
  String get todayGeneration => _localizedStrings['today_generation']!;
  String get totalGeneration => _localizedStrings['total_generation']!;
  String get monthlyGeneration => _localizedStrings['monthly_generation']!;
  String get yearlyGeneration => _localizedStrings['yearly_generation']!;
  String get totalGenerationAll => _localizedStrings['total_generation_all']!;
  String get socialContribution => _localizedStrings['social_contribution']!;
  String get coalSaved => _localizedStrings['coal_saved']!;
  String get co2Reduction => _localizedStrings['co2_reduction']!;
  String get treeEquivalent => _localizedStrings['tree_equivalent']!;

  // 设备
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
  String get all => _localizedStrings['all']!;
  String get normal => _localizedStrings['normal']!;
  String get inverter => _localizedStrings['inverter']!;
  String get collector => _localizedStrings['collector']!;

  // 设备详情分组
  String get acParams => _localizedStrings['ac_params']!;
  String get pvParams => _localizedStrings['pv_params']!;
  String get batteryParams => _localizedStrings['battery_params']!;
  String get systemStatus => _localizedStrings['system_status']!;
  String get energyStats => _localizedStrings['energy_stats']!;
  String get deviceInfo => _localizedStrings['device_info']!;
  String get controlCommand => _localizedStrings['control_command']!;
  String get noControlCommand => _localizedStrings['no_control_command']!;

  // 时间
  String get day => _localizedStrings['day']!;
  String get month => _localizedStrings['month']!;
  String get year => _localizedStrings['year']!;
  String get total => _localizedStrings['total']!;
  String get powerGeneration => _localizedStrings['power_generation']!;
  String get chargeAmount => _localizedStrings['charge_amount']!;
  String get dischargeAmount => _localizedStrings['discharge_amount']!;
  String get load => _localizedStrings['load']!;
  String get time => _localizedStrings['time']!;
  String get timeJustNow => _localizedStrings['time_just_now']!;

  // 告警
  String get alarmList => _localizedStrings['alarm_list']!;
  String get alarmDetail => _localizedStrings['alarm_detail']!;
  String get faultDiagnosis => _localizedStrings['fault_diagnosis']!;
  String get contactInstaller => _localizedStrings['contact_installer']!;
  String get contactService => _localizedStrings['contact_service']!;
  String get processed => _localizedStrings['processed']!;
  String get unprocessed => _localizedStrings['unprocessed']!;
  String get severe => _localizedStrings['severe']!;
  String get warningLevel => _localizedStrings['warning_level']!;
  String get infoLevel => _localizedStrings['info_level']!;
  String get important => _localizedStrings['important']!;
  String get general => _localizedStrings['general']!;
  String get recentAlarms => _localizedStrings['recent_alarms']!;
  String get viewAll => _localizedStrings['view_all']!;
  String get noAlarms => _localizedStrings['no_alarms']!;
  String get unknownAlarm => _localizedStrings['unknown_alarm']!;

  // 能源统计
  String get pvGeneration => _localizedStrings['pv_generation']!;
  String get batteryCharge => _localizedStrings['battery_charge']!;
  String get batteryDischarge => _localizedStrings['battery_discharge']!;
  String get inverterOutput => _localizedStrings['inverter_output']!;
  String get gridInput => _localizedStrings['grid_input']!;
  String get gridOutput => _localizedStrings['grid_output']!;
  String get powerTrend => _localizedStrings['power_trend']!;
  String get energyTrend => _localizedStrings['energy_trend']!;
  String get selectDate => _localizedStrings['select_date']!;
  String get trend7Days => _localizedStrings['trend_7days']!;
  String get generation => _localizedStrings['generation']!;
  String get consumption => _localizedStrings['consumption']!;
  String get dataOverview => _localizedStrings['data_overview']!;
  String get totalDevices => _localizedStrings['total_devices']!;
  String get deviceStatusDistribution => _localizedStrings['device_status_distribution']!;
  String get stationGenerationRanking => _localizedStrings['station_generation_ranking']!;
  String get failedToLoad => _localizedStrings['failed_to_load']!;

  // OTA
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
  String get localFirmwareUpgrade => _localizedStrings['local_firmware_upgrade']!;
  String get selectFirmware => _localizedStrings['select_firmware']!;
  String get pushFirmware => _localizedStrings['push_firmware']!;
  String get upgradeResult => _localizedStrings['upgrade_result']!;
  String get currentDevice => _localizedStrings['current_device']!;
  String get newVersionFound => _localizedStrings['new_version_found']!;
  String get startUpgrade => _localizedStrings['start_upgrade']!;
  String get firmwareList => _localizedStrings['firmware_list']!;
  String get alreadyLatest => _localizedStrings['already_latest']!;
  String get deviceUpgrading => _localizedStrings['device_upgrading']!;

  // OTA 补充
  String get otaTitle => _localizedStrings['ota_title']!;
  String get downloaded => _localizedStrings['downloaded']!;
  String get upgradeComplete => _localizedStrings['upgrade_complete']!;
  String get sendingUpgradeCommand => _localizedStrings['sending_upgrade_command']!;
  String get preDownloading => _localizedStrings['pre_downloading']!;
  String get preDownloadFirmware => _localizedStrings['pre_download_firmware']!;
  String get noFirmware => _localizedStrings['no_firmware']!;
  String get connectionFailed => _localizedStrings['connection_failed']!;
  String get locationPermissionRequired => _localizedStrings['location_permission_required']!;
  String get enableLocationService => _localizedStrings['enable_location_service']!;
  String get connectionFailedNoHotspot => _localizedStrings['connection_failed_no_hotspot']!;
  String get connectedHotspotCannotAccess => _localizedStrings['connected_hotspot_cannot_access']!;
  String get tryFollowing => _localizedStrings['try_following']!;
  String get disableMobileData => _localizedStrings['disable_mobile_data']!;
  String get ensureWifiConnected => _localizedStrings['ensure_wifi_connected']!;
  String get waitAndRetry => _localizedStrings['wait_and_retry']!;
  String get currentHotspot => _localizedStrings['current_hotspot']!;
  String get deviceIpLabel => _localizedStrings['device_ip_label']!;
  String get firmwareFileNotFound => _localizedStrings['firmware_file_not_found']!;
  String get uploadCompleteWaitReboot => _localizedStrings['upload_complete_wait_reboot']!;
  String get upgradeTimeout => _localizedStrings['upgrade_timeout']!;
  String get idleStatus => _localizedStrings['idle']!;
  String get uploadingStatus => _localizedStrings['uploading']!;
  String get firmwareDownloadHint => _localizedStrings['firmware_download_hint']!;
  String get downloadFirmware => _localizedStrings['download_firmware']!;
  String get firmwareReady => _localizedStrings['firmware_ready']!;
  String get scanningDeviceHotspot => _localizedStrings['scanning_device_hotspot']!;
  String get connected => _localizedStrings['connected']!;
  String get connectDeviceAp => _localizedStrings['connect_device_ap']!;
  String get autoScanHint => _localizedStrings['auto_scan_hint']!;
  String get rescanHotspot => _localizedStrings['rescan_hotspot']!;
  String get checkConnection => _localizedStrings['check_connection']!;
  String get pushingFirmware => _localizedStrings['pushing_firmware']!;
  String get doNotDisconnect => _localizedStrings['do_not_disconnect']!;
  String get firmwareVerifyFailed => _localizedStrings['firmware_verify_failed']!;
  String get firmwareCorruptedHint => _localizedStrings['firmware_corrupted_hint']!;
  String get redownload => _localizedStrings['redownload']!;
  String get configureControlFieldsHint => _localizedStrings['configure_control_fields_hint']!;
  String get deviceOfflineWarning => _localizedStrings['device_offline_warning']!;
  String get yesLabel => _localizedStrings['yes']!;
  String get noLabel => _localizedStrings['no']!;
  String get commandPrefix => _localizedStrings['command_prefix']!;

  // 网络/本地
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
  String get configFailed => _localizedStrings['config_failed']!;
  String get switchWifi => _localizedStrings['switch_wifi']!;

  // 个人中心
  String get personalCenter => _localizedStrings['personal_center']!;
  String get changePassword => _localizedStrings['change_password']!;
  String get about => _localizedStrings['about']!;
  String get notificationSettings => _localizedStrings['notification_settings']!;
  String get deviceShare => _localizedStrings['device_share']!;

  // 设置
  String get languageSwitch => _localizedStrings['language_switch']!;
  String get darkMode => _localizedStrings['dark_mode']!;
  String get systemSettings => _localizedStrings['system_settings']!;
  String get connectionSettings => _localizedStrings['connection_settings']!;
  String get displaySettings => _localizedStrings['display_settings']!;
  String get generalSettings => _localizedStrings['general_settings']!;
  String get localModeDesc => _localizedStrings['local_mode_desc']!;
  String get unitSwitch => _localizedStrings['unit_switch']!;
  String get customServer => _localizedStrings['custom_server']!;
  String get timezone => _localizedStrings['timezone']!;
  String get selectTimezone => _localizedStrings['select_timezone']!;
  String get selectPowerUnit => _localizedStrings['select_power_unit']!;
  String get serverAddress => _localizedStrings['server_address']!;
  String get serverHint => _localizedStrings['server_hint']!;
  String get serverSaved => _localizedStrings['server_saved']!;
  String get resetSettings => _localizedStrings['reset_settings']!;
  String get resetConfirm => _localizedStrings['reset_confirm']!;
  String get resetAll => _localizedStrings['reset_all']!;
  String get settingsReset => _localizedStrings['settings_reset']!;
  String get localModeOn => _localizedStrings['local_mode_on']!;
  String get localModeOff => _localizedStrings['local_mode_off']!;
  String get darkModeOn => _localizedStrings['dark_mode_on']!;
  String get darkModeOff => _localizedStrings['dark_mode_off']!;

  // 角色
  String get roleAdmin => _localizedStrings['role_admin']!;
  String get roleAgent => _localizedStrings['role_agent']!;
  String get roleInstaller => _localizedStrings['role_installer']!;
  String get roleUser => _localizedStrings['role_user']!;
  String get overview => _localizedStrings['overview']!;

  // 设备控制
  String get commandSent => _localizedStrings['command_sent']!;
  String get localServiceUnavailable => _localizedStrings['local_service_unavailable']!;

  // 配网
  String get provisionSuccess => _localizedStrings['provision_success']!;
  String get provisionFailed => _localizedStrings['provision_failed']!;

  // 天气
  String get weatherInfo => _localizedStrings['weather_info']!;

  // 电站详情 / 首页补充
  String get stationNotFound => _localizedStrings['station_not_found']!;
  String get clearFilter => _localizedStrings['clear_filter']!;
  String get tapPlusToCreate => _localizedStrings['tap_plus_to_create']!;
  String get pvInverterMonitor => _localizedStrings['pv_inverter_monitor']!;
  String get addNewPvStation => _localizedStrings['add_new_pv_station']!;
  String get scanOrManualAdd => _localizedStrings['scan_or_manual_add']!;
  String get configWifiForDevice => _localizedStrings['config_wifi_for_device']!;
  String get treeCount => _localizedStrings['tree_count']!;
  String get china => _localizedStrings['china']!;

  // 认证补充
  String get pleaseInputAccount => _localizedStrings['please_input_account']!;
  String get pleaseInputPassword => _localizedStrings['please_input_password']!;
  String get passwordLength => _localizedStrings['password_length']!;
  String get registerNow => _localizedStrings['register_now']!;
  String get wechat => _localizedStrings['wechat']!;
  String get phoneOrEmailOrUsername => _localizedStrings['phone_or_email_or_username']!;
  String get inputPhoneEmailUsername => _localizedStrings['input_phone_email_username']!;
  String get pleaseInputEmail => _localizedStrings['please_input_email']!;
  String get pleaseInputCorrectEmail => _localizedStrings['please_input_correct_email']!;
  String get verificationCodeSent => _localizedStrings['verification_code_sent']!;
  String get emailVerificationCode => _localizedStrings['email_verification_code']!;
  String get pleaseInputVerificationCode => _localizedStrings['please_input_verification_code']!;
  String get pleaseInputCorrectCode => _localizedStrings['please_input_correct_code']!;
  String get pleaseInputPhone => _localizedStrings['please_input_phone']!;
  String get phoneTooShort => _localizedStrings['phone_too_short']!;
  String get pleaseInputUsername => _localizedStrings['please_input_username']!;
  String get usernameTooShort => _localizedStrings['username_too_short']!;
  String get confirmPassword => _localizedStrings['confirm_password']!;
  String get pleaseConfirmPassword => _localizedStrings['please_confirm_password']!;
  String get passwordNotMatch => _localizedStrings['password_not_match']!;
  String get loginNow => _localizedStrings['login_now']!;
  String get pleaseInputCorrectPhone => _localizedStrings['please_input_correct_phone']!;
  String get pleaseInput11digitPhone => _localizedStrings['please_input_11digit_phone']!;
  String get pleaseInput6digitCode => _localizedStrings['please_input_6digit_code']!;
  String get newPassword => _localizedStrings['new_password']!;
  String get pleaseInputNewPassword => _localizedStrings['please_input_new_password']!;
  String get passwordResetSuccess => _localizedStrings['password_reset_success']!;
  String get returnToLogin => _localizedStrings['return_to_login']!;
  String get pvInverter => _localizedStrings['pv_inverter']!;
  String get smartMonitorPlatform => _localizedStrings['smart_monitor_platform']!;
  String get checkUpdateFailed => _localizedStrings['check_update_failed']!;
  String get versionCheck => _localizedStrings['version_check']!;
  String get alreadyLatestVersion => _localizedStrings['already_latest_version']!;
  String get versionNumber => _localizedStrings['version_number']!;
  String get updateContent => _localizedStrings['update_content']!;
  String get updateLater => _localizedStrings['update_later']!;
  String get goUpdate => _localizedStrings['go_update']!;
  String get updateNow => _localizedStrings['update_now']!;
  String get aboutUs => _localizedStrings['about_us']!;
  String get pvInverterSmartMonitor => _localizedStrings['pv_inverter_smart_monitor']!;
  String get appVersion => _localizedStrings['version']!;
  String get copyright => _localizedStrings['copyright']!;
  String get userAgreement => _localizedStrings['user_agreement']!;
  String get privacyPolicy => _localizedStrings['privacy_policy']!;
  String get passwordChanged => _localizedStrings['password_changed']!;
  String get originalPassword => _localizedStrings['original_password']!;
  String get confirmChange => _localizedStrings['confirm_change']!;
  String get passwordNotConsistent => _localizedStrings['password_not_consistent']!;
  String get inputPhoneEmailUsernameHint => _localizedStrings['input_phone_email_username_hint']!;
  String get inputPasswordHint => _localizedStrings['input_password_hint']!;
  String get forgotPasswordQ => _localizedStrings['forgot_password_q']!;
  String get inputNewPasswordHint => _localizedStrings['input_new_password_hint']!;
  String get pleaseInputRegisterPhone => _localizedStrings['please_input_register_phone']!;
  String get pleaseInputCorrect11digitPhone => _localizedStrings['please_input_correct_11digit_phone']!;
  String get goToUpdate => _localizedStrings['go_to_update']!;
  String get downloadProgress => _localizedStrings['download_progress']!;

  // 新增 getter
  String get myProfile => _localizedStrings['my_profile']!;
  String roleLabel(String role) => str('role_label', {'role': role});
  String get logout => _localizedStrings['logout']!;
  String get logoutConfirm => _localizedStrings['logout_confirm']!;
  String get markProcessed => _localizedStrings['mark_processed']!;
  String get markProcessedSuccess => _localizedStrings['mark_processed_success']!;
  String get processing => _localizedStrings['processing']!;
  String get alarmInfo => _localizedStrings['alarm_info']!;
  String get alarmCode => _localizedStrings['alarm_code']!;
  String get alarmDescription => _localizedStrings['alarm_description']!;
  String get possibleCauses => _localizedStrings['possible_causes']!;
  String get suggestedActions => _localizedStrings['suggested_actions']!;
  String get deviceSn => _localizedStrings['device_sn']!;
  String get deviceModel => _localizedStrings['device_model']!;
  String get firmwareVersion => _localizedStrings['firmware_version']!;
  String get timeInfo => _localizedStrings['time_info']!;
  String get occurrenceTime => _localizedStrings['occurrence_time']!;
  String get recoveryTime => _localizedStrings['recovery_time']!;
  String get processTime => _localizedStrings['process_time']!;
  String get noInstallerContact => _localizedStrings['no_installer_contact']!;
  String get noAlarmDescription => _localizedStrings['no_alarm_description']!;
  String get pleaseContactService => _localizedStrings['please_contact_service']!;
  String get upgradeDetail => _localizedStrings['upgrade_detail']!;
  String get deviceLabel => _localizedStrings['device_label']!;
  String get cancelUpgrade => _localizedStrings['cancel_upgrade']!;
  String get upgradeCompleted => _localizedStrings['upgrade_completed']!;
  String get firmwareUpdatedSuccess => _localizedStrings['firmware_updated_success']!;
  String get upgradeFailedTitle => _localizedStrings['upgrade_failed_title']!;
  String get modelLabel => _localizedStrings['model_label']!;
  String get firmwareLabel => _localizedStrings['firmware_label']!;
  String get noUpgradableDevices => _localizedStrings['no_upgradable_devices']!;
  String get upgradingDevice => _localizedStrings['upgrading_device']!;
  String get upgradeCompletedStatus => _localizedStrings['upgrade_completed_status']!;
  String get loadingData => _localizedStrings['loading_data']!;
  String get messagesAlarm => _localizedStrings['messages_alarm']!;
  String get networkError => _localizedStrings['network_error']!;
  String get unauthorized => _localizedStrings['unauthorized']!;
  String get forbidden => _localizedStrings['forbidden']!;
  String get notFound => _localizedStrings['not_found']!;
  String get serverError => _localizedStrings['server_error']!;
  String get requestFailed => _localizedStrings['request_failed']!;
  String get responseFormatError => _localizedStrings['response_format_error']!;
  String get loadFailedNetwork => _localizedStrings['load_failed_network']!;
  String get commandAlreadySent => _localizedStrings['command_already_sent']!;
  String get noNetworkCached => _localizedStrings['no_network_cached']!;
  String ratedPower(String power) => str('rated_power', {'power': power});
  String get confirmParamModify => _localizedStrings['confirm_param_modify']!;
  String get provisionSuccessWifi => _localizedStrings['provision_success_wifi']!;
  String get wifiPermissionHint => _localizedStrings['wifi_permission_hint']!;
  String get locationServiceHint => _localizedStrings['location_service_hint']!;
  String get scanFailed => _localizedStrings['scan_failed']!;
  String get pleaseInputWifiName => _localizedStrings['please_input_wifi_name']!;
  String get deviceProvisioning => _localizedStrings['device_provisioning']!;
  String get smartProvision => _localizedStrings['smart_provision']!;
  String get hotspotProvision => _localizedStrings['hotspot_provision']!;
  String get connectDeviceHotspot => _localizedStrings['connect_device_hotspot']!;
  String get scanning => _localizedStrings['scanning']!;
  String get scanNearInverters => _localizedStrings['scan_near_inverters']!;
  String foundNInverters(String count) => str('found_n_inverters', {'count': count});
  String get noInverterFound => _localizedStrings['no_inverter_found']!;
  String get ensureDevicePowered => _localizedStrings['ensure_device_powered']!;
  String connectedTo(String name) => str('connected_to', {'name': name});
  String get disconnect => _localizedStrings['disconnect']!;
  String get scanNearbyWifi => _localizedStrings['scan_nearby_wifi']!;
  String get scanByPhoneHint => _localizedStrings['scan_by_phone_hint'] ?? 'Scan WiFi using phone';
  String get clickWifiToFill => _localizedStrings['click_wifi_to_fill']!;
  String get wifiName => _localizedStrings['wifi_name']!;
  String get clickAboveOrManual => _localizedStrings['click_above_or_manual']!;
  String get wifiPassword => _localizedStrings['wifi_password']!;
  String get inputWifiPassword => _localizedStrings['input_wifi_password']!;
  String get sendingProvisionInfo => _localizedStrings['sending_provision_info']!;
  String get stopProvision => _localizedStrings['stop_provision']!;
  String get provisionStarted => _localizedStrings['provision_started']!;
  String get noPushChannel => _localizedStrings['no_push_channel']!;
  String get otaUpgradeNotification => _localizedStrings['ota_upgrade_notification']!;
  String get firmwareUpgradeNotification => _localizedStrings['firmware_upgrade_notification']!;

  // Dashboard / 设备详情
  String get acOutputPower => _localizedStrings['ac_output_power']!;
  String get loadRate => _localizedStrings['load_rate']!;
  String get frequency => _localizedStrings['frequency']!;
  String get acOutput => _localizedStrings['ac_output']!;
  String get batteryBms => _localizedStrings['battery_bms']!;
  String get pvMppt => _localizedStrings['pv_mppt']!;
  String get loadLabel => _localizedStrings['load_label']!;
  String get electricMeter => _localizedStrings['electric_meter']!;
  String get energyStatsLabel => _localizedStrings['energy_stats_label']!;
  String get systemStatusLabel => _localizedStrings['system_status_label']!;
  String get voltage => _localizedStrings['voltage']!;
  String get current => _localizedStrings['current']!;
  String get chargeDischargeStatus => _localizedStrings['charge_discharge_status']!;
  String get pvVoltage => _localizedStrings['pv_voltage']!;
  String get pvCurrent => _localizedStrings['pv_current']!;
  String get pvPower => _localizedStrings['pv_power']!;
  String get activePower => _localizedStrings['active_power']!;
  String get dailyPvGeneration => _localizedStrings['daily_pv_generation']!;
  String get totalPvGeneration => _localizedStrings['total_pv_generation']!;
  String get runningTime => _localizedStrings['running_time']!;
  String get workStatus => _localizedStrings['work_status']!;
  String get faultCode => _localizedStrings['fault_code']!;
  String get alarmCodeLabel => _localizedStrings['alarm_code_label']!;
  String get efficiency => _localizedStrings['efficiency']!;
  String get inverterTemp => _localizedStrings['inverter_temp']!;
  String get mosTemp => _localizedStrings['mos_temp']!;
  String get lastUpdate => _localizedStrings['last_update']!;
  String get historyCurve => _localizedStrings['history_curve']!;

  // 参数设置
  String get searchParams => _localizedStrings['search_params']!;
  String get noParams => _localizedStrings['no_params']!;
  String get paramSetSuccess => _localizedStrings['param_set_success']!;
  String get applyChanges => _localizedStrings['apply_changes']!;
  String get inputParam => _localizedStrings['input_param']!;

  // 添加设备
  String get selectStation => _localizedStrings['select_station']!;
  String get selectStationForDevice => _localizedStrings['select_station_for_device']!;
  String get noStationsYet => _localizedStrings['no_stations_yet']!;
  String get createStationFirst => _localizedStrings['create_station_first']!;
  String alreadyBoundNDevices(String count) => str('already_bound_n_devices', {'count': count});
  String get addingDevice => _localizedStrings['adding_device']!;
  String get continueScan => _localizedStrings['continue_scan']!;
  String get finish => _localizedStrings['finish']!;
  String get pointSnAtScan => _localizedStrings['point_sn_at_scan']!;
  String get autoFlash => _localizedStrings['auto_flash']!;
  String get scanRecords => _localizedStrings['scan_records']!;
  String get bindSuccess => _localizedStrings['bind_success']!;
  String get bindFailed => _localizedStrings['bind_failed']!;
  String get manualInputSn => _localizedStrings['manual_input_sn']!;
  String get snFormatHint => _localizedStrings['sn_format_hint']!;
  String get deviceSnLabel => _localizedStrings['device_sn_label']!;
  String get input16DigitSn => _localizedStrings['input_16digit_sn']!;
  String get bindDevice => _localizedStrings['bind_device']!;
  String get qrNotRecognized => _localizedStrings['qr_not_recognized']!;
  String get checksumMismatch => _localizedStrings['checksum_mismatch']!;
  String get continueAdd => _localizedStrings['continue_add']!;
  String get pleaseInputSn => _localizedStrings['please_input_sn']!;

  // 电站
  String get newStation => _localizedStrings['new_station']!;
  String get stationInfo => _localizedStrings['station_info']!;
  String get fillStationInfo => _localizedStrings['fill_station_info']!;
  String get region => _localizedStrings['region']!;
  String get selectInstallLocation => _localizedStrings['select_install_location']!;
  String get createStationBtn => _localizedStrings['create_station_btn']!;
  String get pleaseInput => _localizedStrings['please_input']!;
  String get selectRegion => _localizedStrings['select_region']!;
  String get editStation => _localizedStrings['edit_station']!;
  String get saveChanges => _localizedStrings['save_changes']!;
  String get otherGroup => _localizedStrings['other_group']!;

  // 配网补充
  String get smartConfigModeDesc => _localizedStrings['smart_config_mode_desc']!;
  String get smartConfigTimeoutHint => _localizedStrings['smart_config_timeout_hint']!;
  String get bleProvision => _localizedStrings['ble_provision'] ?? 'BLE Config';
  String get bleScanning => _localizedStrings['ble_scanning'] ?? 'Scanning BLE devices...';
  String bleDeviceFound(String count) => str('ble_device_found', {'count': count});
  String get bleNoDeviceFound => _localizedStrings['ble_no_device_found'] ?? 'No BLE devices found';
  String get bleConnecting => _localizedStrings['ble_connecting'] ?? 'Connecting to device...';
  String get bleConnected => _localizedStrings['ble_connected'] ?? 'Connected';
  String get bleReadingInfo => _localizedStrings['ble_reading_info'] ?? 'Reading device info...';
  String get bleSubscribing => _localizedStrings['ble_subscribing'] ?? 'Subscribing to status...';
  String get bleWritingCredentials => _localizedStrings['ble_writing_credentials'] ?? 'Writing WiFi credentials...';
  String get bleWaitingResult => _localizedStrings['ble_waiting_result'] ?? 'Waiting for provisioning result...';
  String get bleSuccess => _localizedStrings['ble_success'] ?? 'Provisioning success';
  String get bleFailed => _localizedStrings['ble_failed'] ?? 'Provisioning failed';
  String get bleTimeout => _localizedStrings['ble_timeout'] ?? 'Provisioning timeout';
  String get bleError => _localizedStrings['ble_error'] ?? 'Provisioning error';
  String get bleDeviceSn => _localizedStrings['ble_device_sn'] ?? 'Device SN';
  String get bleFirmwareVersion => _localizedStrings['ble_firmware_version'] ?? 'Firmware Version';
  String get bleMacAddress => _localizedStrings['ble_mac_address'] ?? 'MAC Address';
  String get bleRssi => _localizedStrings['ble_rssi'] ?? 'Signal Strength';
  String get bleConnect => _localizedStrings['ble_connect'] ?? 'Connect';
  String get bleDisconnect => _localizedStrings['ble_disconnect'] ?? 'Disconnect';
  String get bleRetry => _localizedStrings['ble_retry'] ?? 'Retry';
  String get bleBluetoothOff => _localizedStrings['ble_bluetooth_off'] ?? 'Bluetooth is off';
  String get blePermissionRequired => _localizedStrings['ble_permission_required'] ?? 'Bluetooth permission required';
  String get bleLocationRequired => _localizedStrings['ble_location_required'] ?? 'Location permission required';
  String get bleModeDesc => _localizedStrings['ble_mode_desc'] ?? 'BLE Config: Scan devices via Bluetooth, configure WiFi directly without switching networks';
  String get bleScanDevice => _localizedStrings['ble_scan_device'] ?? 'Scan BLE Devices';
  String get bleDeviceName => _localizedStrings['ble_device_name'] ?? 'Device Name';
  String get bleProvisionSuccess => _localizedStrings['ble_provision_success'] ?? 'Provisioning success! Device is connecting to WiFi...';
  String get bleProvisionWaiting => _localizedStrings['ble_provision_waiting'] ?? 'Provisioning success, waiting for device to come online...';
  String get provisionReady => _localizedStrings['provision_ready']!;
  String get provisionTimeout => _localizedStrings['provision_timeout']!;
  String get provisionFailedX => _localizedStrings['provision_failed_x']!;
  String connectingSsid(String ssid) => str('connecting_ssid', {'ssid': ssid});
  String get waitingStableConnection => _localizedStrings['waiting_stable_connection']!;
  String get noDeviceHotspotRetry => _localizedStrings['no_device_hotspot_retry']!;
  String connectedScanning(String ssid) => str('connected_scanning', {'ssid': ssid});
  String connectionSsidFailed(String ssid) => str('connection_ssid_failed', {'ssid': ssid});
  String get scanningWifiViaDevice => _localizedStrings['scanning_wifi_via_device']!;
  String get noWifiFoundInputManually => _localizedStrings['no_wifi_found_input_manually']!;
  String foundNWifi(String count) => str('found_n_wifi', {'count': count});
  String selectedWifiInputPassword(String ssid) => str('selected_wifi_input_password', {'ssid': ssid});
  String get provisionSuccessConnecting => _localizedStrings['provision_success_connecting']!;
  String provisionCompleteWifiIp(String ssid, String ip) => str('provision_complete_wifi_ip', {'ssid': ssid, 'ip': ip});
  String waitingDeviceConnectionN(String step) => str('waiting_device_connection_n', {'step': step});
  String get configSentDeviceRestart => _localizedStrings['config_sent_device_restart']!;
  String get deviceOnlineWifi => _localizedStrings['device_online_wifi']!;
  String get switchedToRemoteMode => _localizedStrings['switched_to_remote_mode']!;
  String get deviceOnline => _localizedStrings['device_online']!;
  String get provisionSuccessWaiting => _localizedStrings['provision_success_waiting']!;

  // 本地连接补充
  String get localConnection => _localizedStrings['local_connection']!;
  String get localModeDirectAp => _localizedStrings['local_mode_direct_ap']!;
  String get remoteModeCloud => _localizedStrings['remote_mode_cloud']!;
  String get apDisconnectWarning => _localizedStrings['ap_disconnect_warning']!;
  String get scanDevices => _localizedStrings['scan_devices']!;
  String get noDeviceFound => _localizedStrings['no_device_found']!;
  String get ensureDeviceApMode => _localizedStrings['ensure_device_ap_mode']!;
  String deviceApCount(String count) => str('device_ap_count', {'count': count});
  String lanDeviceCount(String count) => str('lan_device_count', {'count': count});
  String get apConnected => _localizedStrings['ap_connected']!;
  String get apCommTestFailed => _localizedStrings['ap_comm_test_failed']!;
  String get localProvince => _localizedStrings['local_province']!;
  String get localCity => _localizedStrings['local_city']!;
  String get localDistrict => _localizedStrings['local_district']!;
  String get pleaseSelectProvince => _localizedStrings['please_select_province']!;
  String get pleaseSelectCity => _localizedStrings['please_select_city']!;
  String get pleaseSelectDistrict => _localizedStrings['please_select_district']!;
  String get stationName => _localizedStrings['station_name']!;
  String get stationNameHint => _localizedStrings['station_name_hint']!;
  String get capacityAutoCalculate => _localizedStrings['capacity_auto_calculate']!;
  String get detailAddress => _localizedStrings['detail_address']!;
  String get detailAddressHint => _localizedStrings['detail_address_hint']!;
  String get selectProvinceCityDistrict => _localizedStrings['select_province_city_district']!;
  String get provinceLabel => _localizedStrings['province']!;
  String get cityLabel => _localizedStrings['city']!;
  String get districtLabel => _localizedStrings['district']!;
  String get installedCapacity => _localizedStrings['installed_capacity']!;
  String get panelCount => _localizedStrings['panel_count']!;
  String get peakPrice => _localizedStrings['peak_price']!;
  String get valleyPrice => _localizedStrings['valley_price']!;
  String get latitude => _localizedStrings['latitude']!;
  String get longitude => _localizedStrings['longitude']!;
  String get paramModified => _localizedStrings['param_modified']!;
  String get paramOn => _localizedStrings['param_on']!;
  String get paramOff => _localizedStrings['param_off']!;
  String paramModifiedCount(String count) => str('param_modified_count', {'count': count});
  String get loadCurrentWifi => _localizedStrings['load_current_wifi']!;
  String connectWifiFirst(String wifi) => str('connect_wifi_first', {'wifi': wifi});

  // Dashboard / 概览补充
  String get snFormatError => _localizedStrings['sn_format_error']!;
  String get snConfirmAdd => _localizedStrings['sn_confirm_add']!;
  String get flashLight => _localizedStrings['flash_light']!;
  String get flipCamera => _localizedStrings['flip_camera']!;
  String get snFormatDesc => _localizedStrings['sn_format_desc']!;
  String nDevices(String count) => str('n_devices', {'count': count});
  String get stationCount => str('station_count');
  String stationCountParam(String count) => str('station_count', {'count': count});
  String get offlineDataHint => _localizedStrings['offline_data_hint']!;

  // 国际化补充
  String get inverterLabel => _localizedStrings['inverter_label']!;
  String get batteryLabel => _localizedStrings['battery_label']!;
  String get gridLabel => _localizedStrings['grid_label']!;
  String get deviceTypeInverter => _localizedStrings['device_type_inverter']!;
  String get deviceTypeCollector => _localizedStrings['device_type_collector']!;
  String get deviceTypeStorage => _localizedStrings['device_type_storage']!;
  String get pushNotification => _localizedStrings['push_notification']!;
  String get pushNotificationDesc => _localizedStrings['push_notification_desc']!;
  String get alarmPush => _localizedStrings['alarm_push']!;
  String get alarmPushDesc => _localizedStrings['alarm_push_desc']!;
  String get offlinePush => _localizedStrings['offline_push']!;
  String get offlinePushDesc => _localizedStrings['offline_push_desc']!;
  String get systemMessage => _localizedStrings['system_message']!;
  String get systemMessageDesc => _localizedStrings['system_message_desc']!;
  String get dndMode => _localizedStrings['dnd_mode']!;
  String get startTime => _localizedStrings['start_time']!;
  String get endTime => _localizedStrings['end_time']!;
  String get resetNotifySettings => _localizedStrings['reset_notify_settings']!;
  String get resetNotifyConfirm => _localizedStrings['reset_notify_confirm']!;
  String get notifySettingsReset => _localizedStrings['notify_settings_reset']!;
  String get resetAllNotify => _localizedStrings['reset_all_notify']!;
  String get otherPhone => _localizedStrings['other_phone']!;
  String get inputOtherPhone => _localizedStrings['input_other_phone']!;
  String get viewOnly => _localizedStrings['view_only']!;
  String get controllableLabel => _localizedStrings['controllable']!;
  String get confirmShare => _localizedStrings['confirm_share']!;
  String get currentPassword => _localizedStrings['current_password']!;
  String get newPasswordLabel => _localizedStrings['new_password_label']!;
  String get confirmPasswordLabel => _localizedStrings['confirm_password_label']!;
  String get passwordLengthHint => _localizedStrings['password_length_hint']!;
  String get dangerousParamWarning => _localizedStrings['dangerous_param_warning']!;
  String get confirmChangeDangerous => _localizedStrings['confirm_change_dangerous']!;
  String get provisionSuccessSwitchWifi => _localizedStrings['provision_success_switch_wifi']!;
  String get later => _localizedStrings['later']!;
  String get searchSnOrModel => _localizedStrings['search_sn_or_model']!;
  String get deviceTypeLabelKey => _localizedStrings['device_type_label']!;
  String get ratedPowerLabel => _localizedStrings['rated_power_label']!;
  String get batterySocLabel => _localizedStrings['battery_soc_label']!;
  String get batteryHealthLabel => _localizedStrings['battery_health_label']!;
  String get dailyChargeLabel => _localizedStrings['daily_charge_label']!;
  String get dailyDischargeLabel => _localizedStrings['daily_discharge_label']!;
  String get dailyGenerationLabel => _localizedStrings['daily_generation_label']!;
  String get armFirmwareLabel => _localizedStrings['arm_firmware_label']!;
  String get noDevices => _localizedStrings['no_devices']!;
  String get pleaseInputCurrentPassword => _localizedStrings['please_input_current_password']!;
  String get notificationType => _localizedStrings['notification_type']!;
  String get dndSection => _localizedStrings['dnd_section']!;
  String get messageNotifySettings => _localizedStrings['message_notify_settings']!;
  String shareDeviceDesc(String sn) => str('share_device_desc', {'sn': sn});
  String get sharePermission => _localizedStrings['share_permission']!;

  // 参数设置页
  String get tabChargeDischarge => _localizedStrings['tab_charge_discharge'] ?? 'Charge & Discharge';
  String get tabWorkMode => _localizedStrings['tab_work_mode'] ?? 'Work Mode';
  String get tabAdvanced => _localizedStrings['tab_advanced'] ?? 'Advanced Settings';
  String get settingsEntryDesc => _localizedStrings['settings_entry_desc'] ?? 'View & modify device parameters';
  String settingLabel(String key) => _localizedStrings[key] ?? key;
  String enumLabel(String key) => _localizedStrings[key] ?? key;
  String get settingReadSuccess => _localizedStrings['setting_read_success'] ?? 'Parameters loaded';
  String get settingReadFailed => _localizedStrings['setting_read_failed'] ?? 'Failed to load parameters';
  String get settingSetSuccess => _localizedStrings['setting_set_success'] ?? 'Parameters saved';
  String get settingSetFailed => _localizedStrings['setting_set_failed'] ?? 'Failed to save parameters';
  String get settingForceConfirmTitle => _localizedStrings['setting_force_confirm_title'] ?? 'Confirm Dangerous Operation';
  String get settingForceChargeConfirm => _localizedStrings['setting_force_charge_confirm'] ?? 'Enable force charge?';
  String get settingForceDischargeConfirm => _localizedStrings['setting_force_discharge_confirm'] ?? 'Enable force discharge?';
  String get settingRestartConfirm => _localizedStrings['setting_restart_confirm'] ?? 'Execute fault reset?';
  String get settingAdvancedHint => _localizedStrings['setting_advanced_hint'] ?? 'Modify with caution.';
  String get settingRestartBtn => _localizedStrings['setting_restart_btn'] ?? 'Execute Reset';

  // 错误消息 getter
  String get errUnknownError => _localizedStrings['err_unknown_error'] ?? 'Unknown error';
  String get errInvalidResponse => _localizedStrings['err_invalid_response'] ?? 'Invalid response';
  String get errConnectionTimeout => _localizedStrings['err_connection_timeout'] ?? 'Connection timeout';
  String get errRequestCancelled => _localizedStrings['err_request_cancelled'] ?? 'Request cancelled';
  String get errNoInternet => _localizedStrings['err_no_internet'] ?? 'No internet';
  String get errUnauthorized => _localizedStrings['err_unauthorized'] ?? 'Unauthorized';
  String get errForbidden => _localizedStrings['err_forbidden'] ?? 'Access denied';
  String get errNotFound => _localizedStrings['err_not_found'] ?? 'Not found';
  String get errNetworkError => _localizedStrings['err_network_error'] ?? 'Network error';
  String get errServerError => _localizedStrings['err_server_error'] ?? 'Server error';
  String get errRequestFailed => _localizedStrings['err_request_failed'] ?? 'Request failed';
  String get errResponseFormat => _localizedStrings['err_response_format'] ?? 'Response format error';
  String get errCommandSent => _localizedStrings['err_command_sent'] ?? 'Command sent';
  String get errLocalServiceUnavailable => _localizedStrings['err_local_service_unavailable'] ?? 'Local service unavailable';
  String get errLoadFailed => _localizedStrings['err_load_failed'] ?? 'Failed to load';
  String get errConfigSuccess => _localizedStrings['err_config_success'] ?? 'Config success';
  String get errConfigFailed => _localizedStrings['err_config_failed'] ?? 'Config failed';
  String get errRequestTimeout => _localizedStrings['err_request_timeout'] ?? 'Request timeout';
  String get errWifiConnected => _localizedStrings['err_wifi_connected'] ?? 'WiFi connected';
  String get errWaitingConnection => _localizedStrings['err_waiting_connection'] ?? 'Waiting...';
  String get errDeviceRebooting => _localizedStrings['err_device_rebooting'] ?? 'Rebooting...';
  String get errFieldMetadata => _localizedStrings['err_field_metadata'] ?? 'Failed to get metadata';
  String get errCannotOpenInstaller => _localizedStrings['err_cannot_open_installer'] ?? 'Cannot open installer';

  // 新增 getter
  String get gotIt => _localizedStrings['got_it']!;
  String cannotOpenLink(String url) => str('cannot_open_link', {'url': url});
  String get notHaveAccount => _localizedStrings['not_have_account']!;
  String get createAccount => _localizedStrings['create_account']!;
  String get registerToUseAll => _localizedStrings['register_to_use_all']!;
  String get alreadyHaveAccount => _localizedStrings['already_have_account']!;
  String get alarmNotFound => _localizedStrings['alarm_not_found']!;
  String get userAgreementTitle => _localizedStrings['user_agreement_title']!;
  String get privacyPolicyTitle => _localizedStrings['privacy_policy_title']!;
  String get loggedIn => _localizedStrings['logged_in']!;
  String get myDevices => _localizedStrings['my_devices']!;
  String get myStations => _localizedStrings['my_stations']!;
  String get navHome => _localizedStrings['nav_home']!;
  String get navOverview => _localizedStrings['nav_overview']!;
  String get navDevice => _localizedStrings['nav_device']!;
  String get navAlarm => _localizedStrings['nav_alarm']!;
  String get navProfile => _localizedStrings['nav_profile']!;

  // 新增 getter（不与上面重复的）
  String get recent7DayTrend => _localizedStrings['recent_7day_trend'] ?? '7-Day Trend';
  String get recent30DayTrend => _localizedStrings['recent_30day_trend'] ?? '30-Day Trend';
  String get powerConsumption => _localizedStrings['power_consumption'] ?? 'Consumption';
  String get unitDevices => _localizedStrings['unit_devices'] ?? '';
  String get noDevicesYet => _localizedStrings['no_devices_yet'] ?? 'No devices';
  String get statusOnline => _localizedStrings['status_online'] ?? 'Online';
  String get statusOffline => _localizedStrings['status_offline'] ?? 'Offline';
  String get statusFault => _localizedStrings['status_fault'] ?? 'Fault';
  String get statusAlarm => _localizedStrings['status_alarm'] ?? 'Alarm';
  String get realtimePower => _localizedStrings['realtime_power'] ?? 'Realtime Power';
  String get todayRevenue => _localizedStrings['today_revenue'] ?? 'Today Revenue';
  String get timeDay => _localizedStrings['time_day'] ?? 'Day';
  String get timeWeek => _localizedStrings['time_week'] ?? 'Week';
  String get timeMonth => _localizedStrings['time_month'] ?? 'Month';
  String get timeToday => _localizedStrings['time_today'] ?? 'Today';
  String get timeThisMonth => _localizedStrings['time_this_month'] ?? 'Month';
  String get timeThisYear => _localizedStrings['time_this_year'] ?? 'Year';
  String get timeTotal => _localizedStrings['time_total'] ?? 'Total';
  String get wan => _localizedStrings['wan'] ?? 'W';
  String get groupAcParams => _localizedStrings['group_ac_params'] ?? 'AC Parameters';
  String get groupPvParams => _localizedStrings['group_pv_params'] ?? 'PV Parameters';
  String get groupBatteryParams => _localizedStrings['group_battery_params'] ?? 'Battery Parameters';
  String get groupSystemStatus => _localizedStrings['group_system_status'] ?? 'System Status';
  String get groupEnergyStats => _localizedStrings['group_energy_stats'] ?? 'Energy Stats';
  String get groupDeviceInfo => _localizedStrings['group_device_info'] ?? 'Device Info';
  String get groupControlCmd => _localizedStrings['group_control_cmd'] ?? 'Control Commands';
  String get groupOther => _localizedStrings['group_other'] ?? 'Other';
  String get faultCodeLabel => _localizedStrings['fault_code_label'] ?? 'Fault Code';
  String get firmwareUnknown => _localizedStrings['firmware_unknown'] ?? 'Unknown';
  String get userAgreementContent => _localizedStrings['user_agreement_content'] ?? '';
  String get privacyPolicyContent => _localizedStrings['privacy_policy_content'] ?? '';
  String get searchDeviceHint => _localizedStrings['search_device_hint'] ?? 'Search device name/SN';
  String get pageNotFound => _localizedStrings['page_not_found'] ?? 'Page not found';
  String get armFirmware => _localizedStrings['arm_firmware'] ?? 'ARM FW';
  String get searchStationsHint => _localizedStrings['search_stations_hint'] ?? 'Search station name';
  String get searchAlarmsHint => _localizedStrings['search_alarms_hint'] ?? 'Search alarm device/SN';
  String get inverterListTitle => _localizedStrings['inverter_list_title'] ?? 'Inverter List';
  String get deviceListTitle => _localizedStrings['device_list_title'] ?? 'Device List';
  String get stationListTitle => _localizedStrings['station_list_title'] ?? 'Station List';
  String get offlineCachedData => _localizedStrings['offline_cached_data'] ?? 'No network, cached data';

  // 通知中心
  String get notificationCenter => _localizedStrings['notification_center'] ?? 'Notification Center';
  String get tabAlarms => _localizedStrings['tab_alarms'] ?? 'Alarms';
  String get tabNotifications => _localizedStrings['tab_notifications'] ?? 'Notifications';
  String get noNotifications => _localizedStrings['no_notifications'] ?? 'No notifications';
  String notifyDeviceOnline(String device) => str('notify_device_online', {'device': device});
  String notifyDeviceOffline(String device) => str('notify_device_offline', {'device': device});
  String notifyOtaAvailable(String device) => str('notify_ota_available', {'device': device});
  String notifyAppUpdate(String version) => str('notify_app_update', {'version': version});

  String get confirmExecute => _localizedStrings['confirm_execute'] ?? 'Confirm Execute';

  /// 将英文/中文错误消息翻译为当前语言
  /// 支持 [code] message 格式、英文/中文精确匹配和前缀匹配
  String translateError(String message) {
    // 错误码翻译表（服务端返回的 code → 本地化 key）
    const Map<int, String> _codeMap = {
      4001: 'err_user_not_found',
      4002: 'err_account_disabled',
      4003: 'err_invalid_password',
      4004: 'err_phone_registered',
      4005: 'err_invalid_code',
      4006: 'err_send_code_failed',
      4007: 'err_old_password_wrong',
      4008: 'err_invalid_email',
      4009: 'err_email_registered',
      4029: 'err_too_many_attempts',
    };

    // 先检查 [code] 格式
    final codeMatch = RegExp(r'^\[(\d+)\] (.*)$').firstMatch(message);
    if (codeMatch != null) {
      final code = int.tryParse(codeMatch.group(1) ?? '');
      final rawMsg = codeMatch.group(2) ?? '';
      if (code != null && _codeMap.containsKey(code)) {
        final translated = _localizedStrings[_codeMap[code]!];
        if (translated != null) return translated;
      }
      // code 不在表中，用原始消息继续下面的精确匹配
      message = rawMsg;
    }

    // 精确匹配（英文 + 中文）
    const Map<String, String> _errorKeyMap = {
      'Unknown error': 'err_unknown_error',
      'Invalid response format': 'err_invalid_response',
      'Connection timeout': 'err_connection_timeout',
      'Request cancelled': 'err_request_cancelled',
      'No internet connection': 'err_no_internet',
      'Unauthorized': 'err_unauthorized',
      'Forbidden': 'err_forbidden',
      'Not found': 'err_not_found',
      'Network error': 'err_network_error',
      'Request failed': 'err_request_failed',
      'Response format error': 'err_response_format',
      'Command sent': 'err_command_sent',
      'Local service unavailable': 'err_local_service_unavailable',
      'Failed to load, please check network': 'err_load_failed',
      'Configuration successful': 'err_config_success',
      'Configuration failed': 'err_config_failed',
      'WiFi connected': 'err_wifi_connected',
      'Waiting for connection...': 'err_waiting_connection',
      'Device rebooting...': 'err_device_rebooting',
      'Failed to get field metadata': 'err_field_metadata',
      // 后端错误消息（英文）
      'user not found': 'err_user_not_found',
      'account disabled': 'err_account_disabled',
      'invalid password': 'err_invalid_password',
      'phone already registered': 'err_phone_registered',
      'invalid verification code': 'err_invalid_code',
      'invalid email format': 'err_invalid_email',
      'old password incorrect': 'err_old_password_wrong',
      'generate token failed': 'err_generate_token',
      'password encryption failed': 'err_password_encryption',
      'create user failed': 'err_create_user',
      'update password failed': 'err_update_password',
      'system error': 'err_system_error',
      'invalid request': 'err_invalid_request',
      // 后端错误消息（中文）
      '用户不存在': 'err_user_not_found',
      '账号已禁用': 'err_account_disabled',
      '密码错误': 'err_invalid_password',
      '该手机号已注册': 'err_phone_registered',
      '该手机号未注册': 'err_user_not_found',
      '该邮箱未注册': 'err_user_not_found',
      '该邮箱已注册': 'err_email_registered',
      '验证码错误': 'err_invalid_code',
      '验证码已过期': 'err_code_expired',
      '旧密码不正确': 'err_old_password_wrong',
      '系统错误': 'err_system_error',
    };

    final key = _errorKeyMap[message];
    if (key != null) return _localizedStrings[key] ?? message;

    // 前缀匹配
    if (message.startsWith('Server error:')) {
      final code = message.substring('Server error:'.length).trim();
      return '${_localizedStrings['err_server_error'] ?? 'Server error'}: $code';
    }
    if (message.startsWith('Request timeout:')) {
      return _localizedStrings['err_request_timeout'] ?? 'Request timeout';
    }
    if (message.startsWith('Cannot open installer:')) {
      return _localizedStrings['err_cannot_open_installer'] ?? 'Cannot open installer';
    }
    // 中文动态消息（含变量）
    if (message.contains('登录失败次数过多')) {
      return _localizedStrings['err_login_too_many'] ?? message;
    }
    if (message.contains('验证码发送频繁')) {
      return _localizedStrings['err_code_too_frequent'] ?? message;
    }

    return message;
  }
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
