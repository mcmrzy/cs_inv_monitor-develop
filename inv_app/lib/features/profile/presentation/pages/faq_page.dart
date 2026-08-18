import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:inv_app/core/services/help_center_config_service.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/widgets/settings_widgets.dart';
import 'package:inv_app/core/widgets/skeleton_widgets.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 常见问题页（帮助中心「常见问题」入口的独立页面）
///
/// FAQ 列表由后端 /config/help-center 下发，经 [HelpCenterConfigService]
/// 拉取（会话内缓存，失败回退内置默认值）；点击问题展开答案。
class FaqPage extends StatefulWidget {
  const FaqPage({super.key});

  @override
  State<FaqPage> createState() => _FaqPageState();
}

class _FaqPageState extends State<FaqPage> {
  bool _loading = true;
  List<FaqItem> _faqs = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cfg = await HelpCenterConfigService().fetch();
    if (!mounted) return;
    setState(() {
      _faqs = cfg.faqs;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.helpFaq)),
      body: _loading
          ? const PageSkeleton()
          : _faqs.isEmpty
              ? _buildEmpty(l10n)
              : _buildList(l10n),
    );
  }

  Widget _buildEmpty(AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.help_outline_rounded,
            size: 44.sp,
            color: AppColor.textHint(context),
          ),
          SizedBox(height: 12.h),
          Text(
            l10n.str('help_faq_empty'),
            style: TextStyle(
              fontSize: 14.sp,
              color: AppColor.textHint(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(AppLocalizations l10n) {
    return ListView(
      padding: EdgeInsets.only(bottom: 24.h),
      children: [
        // 头部：条目数量提示
        Padding(
          padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 4.h),
          child: Text(
            l10n.str('help_faq_hint'),
            style: TextStyle(
              fontSize: 12.sp,
              color: AppColor.textHint(context),
            ),
          ),
        ),
        SettingsCard([
          for (final faq in _faqs)
            ExpansionTile(
              shape: const Border(),
              title: Text(
                faq.question,
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w500,
                  color: AppColor.textPrimary(context),
                ),
              ),
              childrenPadding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 14.h),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    faq.answer,
                    style: TextStyle(
                      fontSize: 13.sp,
                      height: 1.5,
                      color: AppColor.textHint(context),
                    ),
                  ),
                ),
              ],
            ),
        ]),
      ],
    );
  }
}
