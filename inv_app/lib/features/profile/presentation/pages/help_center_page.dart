import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:url_launcher/url_launcher.dart';

import 'package:inv_app/core/services/contact_service.dart';
import 'package:inv_app/core/services/help_center_config_service.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/widgets/app_toast.dart';
import 'package:inv_app/core/widgets/settings_widgets.dart';
import 'package:inv_app/features/profile/presentation/pages/faq_page.dart';
import 'package:inv_app/features/support/presentation/pages/work_orders_page.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 帮助中心页（需求 14）
///
/// 区块：
/// - 自助服务：设备/App/系统说明书（文档 URL 由后端 /config/help-center
///   动态下发，经 [HelpCenterConfigService] 拉取，失败回退内置默认值；
///   无 URL 时提示"文档暂未开放"。无 WebView 依赖，用系统浏览器打开）。
/// - 客服支持：电话客服（号码由后端配置下发）+ 在线客服（复用
///   [ContactService]）。
/// - 常见问题：入口行 → 独立 FAQ 页（[FaqPage]，后端配置下发，
///   未配置时不展示入口）。
/// - 我的工单：列表 + 提交表单（对接后端 work-order API，
///   实现见 [WorkOrdersPage]）。
class HelpCenterPage extends StatefulWidget {
  const HelpCenterPage({super.key});

  @override
  State<HelpCenterPage> createState() => _HelpCenterPageState();
}

class _HelpCenterPageState extends State<HelpCenterPage> {
  /// 后端下发的配置；加载完成前使用内置默认值，避免闪烁
  HelpCenterConfig _config = HelpCenterConfig.fallback;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final cfg = await HelpCenterConfigService().fetch();
    if (!mounted) return;
    setState(() => _config = cfg);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.helpCenter)),
      body: ListView(
        padding: EdgeInsets.only(bottom: 24.h),
        children: [
          SettingsSectionTitle(
            icon: Icons.menu_book_rounded,
            title: l10n.helpSelfService,
            accent: AppColors.teal,
          ),
          SettingsCard([
            SettingsValueRow(
              icon: Icons.developer_board_rounded,
              accent: AppColors.teal,
              title: l10n.helpDocDevice,
              subtitle: l10n.helpSelfServiceHint,
              onTap: () => _openDoc(context, _config.deviceManualUrl),
            ),
            SettingsValueRow(
              icon: Icons.phone_android_rounded,
              accent: AppColors.teal,
              title: l10n.helpDocApp,
              subtitle: l10n.helpSelfServiceHint,
              onTap: () => _openDoc(context, _config.appManualUrl),
            ),
            SettingsValueRow(
              icon: Icons.cloud_rounded,
              accent: AppColors.teal,
              title: l10n.helpDocSystem,
              subtitle: l10n.helpSelfServiceHint,
              onTap: () => _openDoc(context, _config.systemManualUrl),
            ),
          ]),
          SettingsSectionTitle(
            icon: Icons.support_agent_rounded,
            title: l10n.helpCustomerService,
            accent: AppColors.blue,
          ),
          SettingsCard([
            SettingsValueRow(
              icon: Icons.phone_rounded,
              accent: AppColors.blue,
              title: l10n.helpPhoneSupport,
              subtitle:
                  '${_config.servicePhone} · ${l10n.helpPhoneSupportHint}',
              onTap: () => ContactService().makePhoneCall(_config.servicePhone),
            ),
            SettingsValueRow(
              icon: Icons.chat_rounded,
              accent: AppColors.blue,
              title: l10n.helpOnlineSupport,
              subtitle: l10n.helpOnlineSupportHint,
              onTap: () => ContactService().openChat(),
            ),
          ]),
          // 常见问题入口（后端配置下发，未配置时不展示；点开进入独立 FAQ 页）
          if (_config.faqs.isNotEmpty) ...[
            SettingsSectionTitle(
              icon: Icons.help_outline_rounded,
              title: l10n.helpFaq,
              accent: AppColors.purple,
            ),
            SettingsCard([
              SettingsValueRow(
                icon: Icons.quiz_rounded,
                accent: AppColors.purple,
                title: l10n.helpFaq,
                subtitle: l10n.str('help_faq_hint'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const FaqPage(),
                  ),
                ),
              ),
            ]),
          ],
          SettingsSectionTitle(
            icon: Icons.assignment_rounded,
            title: l10n.helpWorkOrder,
            accent: AppColors.purple,
          ),
          SettingsCard([
            SettingsValueRow(
              icon: Icons.receipt_long_rounded,
              accent: AppColors.purple,
              title: l10n.helpWorkOrder,
              subtitle: l10n.helpWorkOrderHint,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const WorkOrdersPage(),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Future<void> _openDoc(BuildContext context, String url) async {
    final l10n = AppLocalizations.of(context)!;
    if (url.isEmpty) {
      AppToast.show(context, l10n.helpDocUnavailable, type: ToastType.info);
      return;
    }
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      if (context.mounted) {
        AppToast.show(context, l10n.helpDocUnavailable, type: ToastType.info);
      }
    }
  }
}
