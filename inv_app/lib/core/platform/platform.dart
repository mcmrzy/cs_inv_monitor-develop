/// 平台能力抽象层入口。
///
/// 业务层统一从这里拿 OS 与能力开关；原生插件（wifi_iot / 自研
/// MethodChannel / JPush 等）的平台差异收敛在此目录与各 service 内部。
library;

export 'app_platform.dart';
export 'wifi_ap_controller.dart';
