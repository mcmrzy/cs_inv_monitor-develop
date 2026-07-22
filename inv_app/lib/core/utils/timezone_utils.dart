/// 时区管理工具
/// 后端存储/传输统一使用 UTC, 前端根据站点时区进行本地化显示
library;

import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:inv_app/l10n/app_localizations.dart';

class TimezoneUtils {
  TimezoneUtils._();

  /// 是否已初始化时区数据
  static bool _initialized = false;

  /// 初始化时区数据（必须在使用前调用）
  static void initialize() {
    if (!_initialized) {
      tz_data.initializeTimeZones();
      _initialized = true;
    }
  }

  /// 默认时区
  static const String defaultTimezone = 'Asia/Shanghai';

  /// 常用时区列表 (按UTC偏移量从大到小排序，与后端保持一致)
  static const List<Map<String, String>> commonTimezones = [
    {'id': 'Pacific/Auckland', 'label': 'UTC+12 奥克兰', 'labelZh': 'UTC+12 奥克兰'},
    {'id': 'Australia/Sydney', 'label': 'UTC+10 悉尼', 'labelZh': 'UTC+10 悉尼'},
    {'id': 'Asia/Tokyo', 'label': 'UTC+9 东京', 'labelZh': 'UTC+9 东京'},
    {'id': 'Asia/Seoul', 'label': 'UTC+9 首尔', 'labelZh': 'UTC+9 首尔'},
    {'id': 'Asia/Shanghai', 'label': 'UTC+8 上海', 'labelZh': 'UTC+8 上海'},
    {'id': 'Asia/Singapore', 'label': 'UTC+8 新加坡', 'labelZh': 'UTC+8 新加坡'},
    {'id': 'Asia/Kuala_Lumpur', 'label': 'UTC+8 吉隆坡', 'labelZh': 'UTC+8 吉隆坡'},
    {'id': 'Asia/Manila', 'label': 'UTC+8 马尼拉', 'labelZh': 'UTC+8 马尼拉'},
    {'id': 'Asia/Ho_Chi_Minh', 'label': 'UTC+7 胡志明', 'labelZh': 'UTC+7 胡志明'},
    {'id': 'Asia/Bangkok', 'label': 'UTC+7 曼谷', 'labelZh': 'UTC+7 曼谷'},
    {'id': 'Asia/Jakarta', 'label': 'UTC+7 雅加达', 'labelZh': 'UTC+7 雅加达'},
    {
      'id': 'Asia/Kolkata',
      'label': 'UTC+5:30 加尔各答',
      'labelZh': 'UTC+5:30 加尔各答',
    },
    {'id': 'Asia/Dubai', 'label': 'UTC+4 迪拜', 'labelZh': 'UTC+4 迪拜'},
    {'id': 'Asia/Riyadh', 'label': 'UTC+3 利雅得', 'labelZh': 'UTC+3 利雅得'},
    {'id': 'Asia/Tehran', 'label': 'UTC+3:30 德黑兰', 'labelZh': 'UTC+3:30 德黑兰'},
    {'id': 'Europe/Moscow', 'label': 'UTC+3 莫斯科', 'labelZh': 'UTC+3 莫斯科'},
    {'id': 'Europe/Athens', 'label': 'UTC+2 雅典', 'labelZh': 'UTC+2 雅典'},
    {'id': 'Europe/Berlin', 'label': 'UTC+1 柏林', 'labelZh': 'UTC+1 柏林'},
    {'id': 'Europe/Paris', 'label': 'UTC+1 巴黎', 'labelZh': 'UTC+1 巴黎'},
    {'id': 'Europe/Madrid', 'label': 'UTC+1 马德里', 'labelZh': 'UTC+1 马德里'},
    {'id': 'Africa/Lagos', 'label': 'UTC+1 拉各斯', 'labelZh': 'UTC+1 拉各斯'},
    {'id': 'Europe/London', 'label': 'UTC+0 伦敦', 'labelZh': 'UTC+0 伦敦'},
    {'id': 'America/New_York', 'label': 'UTC-5 纽约', 'labelZh': 'UTC-5 纽约'},
    {'id': 'America/Chicago', 'label': 'UTC-6 芝加哥', 'labelZh': 'UTC-6 芝加哥'},
    {'id': 'America/Denver', 'label': 'UTC-7 丹佛', 'labelZh': 'UTC-7 丹佛'},
    {'id': 'America/Los_Angeles', 'label': 'UTC-8 洛杉矶', 'labelZh': 'UTC-8 洛杉矶'},
    {
      'id': 'America/Mexico_City',
      'label': 'UTC-6 墨西哥城',
      'labelZh': 'UTC-6 墨西哥城',
    },
    {'id': 'America/Sao_Paulo', 'label': 'UTC-3 圣保罗', 'labelZh': 'UTC-3 圣保罗'},
  ];

  /// 根据语言获取时区显示标签
  static String getLabel(String timezoneId, {String langCode = 'en'}) {
    for (final tz in commonTimezones) {
      if (tz['id'] == timezoneId) {
        if (langCode == 'zh') return tz['labelZh'] ?? tz['label'] ?? timezoneId;
        return tz['label'] ?? timezoneId;
      }
    }
    return timezoneId;
  }

  /// 获取时区偏移量的简短显示 (如 "+08:00")
  static String getOffsetLabel(String timezoneId) {
    for (final tz in commonTimezones) {
      if (tz['id'] == timezoneId) {
        final label = tz['label'] ?? '';
        final match = RegExp(r'UTC([+-][\d:]+)').firstMatch(label);
        if (match != null) {
          return match.group(1) ?? '';
        }
      }
    }
    return '';
  }

  /// 从 stations 数据中获取时区
  static String getTimezoneFromStation(Map<String, dynamic>? station) {
    if (station == null) return defaultTimezone;
    return (station['timezone'] as String?) ?? defaultTimezone;
  }

  /// 将 UTC 时间字符串格式化为相对时间（支持国际化）
  static String formatRelativeTime(
    String? dateTimeStr, {
    AppLocalizations? l10n,
  }) {
    if (dateTimeStr == null || dateTimeStr.isEmpty) {
      return l10n?.unknown ?? 'Unknown';
    }
    try {
      final dt = DateTime.parse(dateTimeStr).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (l10n != null) {
        if (diff.inMinutes < 1) return l10n.timeJustNow;
        if (diff.inMinutes < 60) {
          return l10n.str('time_minutes_ago', {'minutes': '${diff.inMinutes}'});
        }
        if (diff.inHours < 24) {
          return l10n.str('time_hours_ago', {'hours': '${diff.inHours}'});
        }
        if (diff.inDays < 30) {
          return l10n.str('time_days_ago', {'days': '${diff.inDays}'});
        }
      } else {
        if (diff.inMinutes < 1) return 'Just now';
        if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
        if (diff.inHours < 24) return '${diff.inHours}h ago';
        if (diff.inDays < 30) return '${diff.inDays}d ago';
      }
      return DateFormat('MM/dd').format(dt);
    } catch (_) {
      return dateTimeStr;
    }
  }

  /// 格式化 UTC 时间为指定时区的时间字符串
  /// [dateTimeStr] UTC 时间字符串
  /// [timezone] 目标时区（如 'Asia/Shanghai'），如果为 null 则使用设备本地时区
  /// [format] 输出格式
  static String formatLocalTime(
    String? dateTimeStr, {
    String format = 'yyyy-MM-dd HH:mm:ss',
    String? timezone,
  }) {
    if (dateTimeStr == null || dateTimeStr.isEmpty) return '-';
    try {
      final dt = DateTime.parse(dateTimeStr);

      // 如果提供了时区，使用该时区转换
      if (timezone != null && timezone.isNotEmpty) {
        initialize(); // 确保时区数据已初始化
        try {
          final location = tz.getLocation(timezone);
          final tzDateTime = tz.TZDateTime.from(dt, location);
          return DateFormat(format).format(tzDateTime);
        } catch (e) {
          // 时区无效时回退到本地时间
          return DateFormat(format).format(dt.toLocal());
        }
      }

      // 否则使用设备本地时区
      return DateFormat(format).format(dt.toLocal());
    } catch (_) {
      return dateTimeStr;
    }
  }

  /// URL 编码时区字符串 (用于天气 API 等外部调用)
  static String encodeTimezoneForUrl(String timezone) {
    return Uri.encodeComponent(timezone);
  }
}
