import 'package:flutter/material.dart';
import 'package:wifi_iot/wifi_iot.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 检查手机 WiFi 是否开启；未开启时弹窗引导开启（Android 10+ 需用户手动开启）。
/// 返回 true 表示 WiFi 已开启（或检查失败不阻断流程），false 表示用户取消开启。
/// 供所有调用 scanWifiNetworks 的页面复用（wifi_config_page / local_mode_page / local_ota_page）。
Future<bool> ensureWifiEnabled(BuildContext context) async {
  try {
    if (await WiFiForIoTPlugin.isEnabled()) return true;
    if (!context.mounted) return false;
    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(ctx)!.str('wifi_off_title')),
        content: Text(AppLocalizations.of(ctx)!.str('wifi_off_hint')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppLocalizations.of(ctx)!.cancel),
          ),
          TextButton(
            onPressed: () async {
              // 请求开启；Android 10+（API 29+）会跳转系统 WiFi 设置页
              try {
                await WiFiForIoTPlugin.setEnabled(
                  true,
                  shouldOpenSettings: true,
                );
              } catch (_) {}
              Navigator.pop(ctx, true);
            },
            child: Text(AppLocalizations.of(ctx)!.str('wifi_enable_now')),
          ),
        ],
      ),
    );
    if (proceed != true || !context.mounted) return false;
    // 用户返回后复查 WiFi 状态
    try {
      return await WiFiForIoTPlugin.isEnabled();
    } catch (_) {
      return false;
    }
  } catch (_) {
    // 检查失败不阻断扫描流程
    return true;
  }
}
