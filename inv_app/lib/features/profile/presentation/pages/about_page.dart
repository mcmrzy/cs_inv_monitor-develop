import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/config/app_config.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  bool _checkingUpdate = false;

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法打开链接: $url'), duration: const Duration(seconds: 2)),
        );
      }
    }
  }

  void _showUserAgreement() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('用户协议'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('光伏逆变器智能监控系统用户协议', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.sp)),
                SizedBox(height: 8.h),
                Text('1. 服务内容\n本系统提供光伏逆变器的远程监控、设备管理、告警通知等功能。\n\n2. 用户责任\n用户应妥善保管账号信息，不得将账号转让或共享给他人。\n\n3. 隐私保护\n我们将严格保护用户的个人信息和设备数据，不会向第三方泄露。\n\n4. 免责声明\n因网络故障、设备故障等不可抗力因素导致的数据丢失或延迟，系统不承担责任。\n\n5. 协议更新\n我们保留随时更新本协议的权利，更新后的协议将在应用内公示。', style: TextStyle(fontSize: 12.sp, height: 1.5)),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
  }

  void _showPrivacyPolicy() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('隐私政策'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('光伏逆变器智能监控系统隐私政策', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.sp)),
                SizedBox(height: 8.h),
                Text('1. 信息收集\n我们收集的信息包括：账号信息、设备信息、运行数据等，用于提供监控服务。\n\n2. 信息使用\n收集的信息仅用于：设备监控、故障诊断、统计分析、优化服务。\n\n3. 信息存储\n数据存储在中国境内的服务器上，采用加密传输和存储技术。\n\n4. 信息共享\n未经用户同意，我们不会将个人信息共享给任何第三方。\n\n5. 信息安全\n我们采用业界标准的安全措施保护用户数据，包括但不限于加密传输、访问控制等。\n\n6. 用户权利\n用户有权查看、修改、删除自己的个人信息，也可申请注销账号。', style: TextStyle(fontSize: 12.sp, height: 1.5)),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
  }

  Future<void> _checkForUpdates() async {
    setState(() => _checkingUpdate = true);

    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      setState(() => _checkingUpdate = false);
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('版本检查'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_outline, size: 48.sp, color: AppColors.success),
              SizedBox(height: 12.h),
              Text(
                '当前已是最新版本',
                style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 4.h),
              Text(
                '版本号: ${AppConfig.version}',
                style: TextStyle(fontSize: 13.sp, color: AppColors.textHint),
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('确定'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('关于我们')),
      body: ListView(
        children: [
          const SizedBox(height: 40),
          Container(
            width: 80.w,
            height: 80.w,
            margin: EdgeInsets.symmetric(horizontal: (MediaQuery.of(context).size.width - 80.w) / 2),
            decoration: BoxDecoration(
              color: AppColors.primary.withAlpha(25),
              borderRadius: BorderRadius.circular(20.r),
            ),
            child: Icon(Icons.solar_power, size: 44.sp, color: AppColors.primary),
          ),
          SizedBox(height: 16.h),
          const Center(
            child: Text(
              '光伏逆变器智能监控',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          SizedBox(height: 4.h),
          Center(
            child: Text(
              '版本: ${AppConfig.version}',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
          ),
          SizedBox(height: 8.h),
          Center(
            child: Text(
              '辰烁科技',
              style: TextStyle(fontSize: 13, color: Colors.grey[500]),
            ),
          ),
          SizedBox(height: 40.h),
          _buildMenuItem(Icons.description_outlined, '用户协议', _showUserAgreement),
          const Divider(height: 1, indent: 50),
          _buildMenuItem(Icons.privacy_tip_outlined, '隐私政策', _showPrivacyPolicy),
          const Divider(height: 1, indent: 50),
          _buildMenuItem(
            Icons.system_update_outlined,
            '检查更新',
            _checkingUpdate ? null : _checkForUpdates,
            trailing: _checkingUpdate
                ? SizedBox(
                    width: 20.w,
                    height: 20.w,
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
          ),
          SizedBox(height: 40.h),
          Center(
            child: Text(
              '© 2026 辰烁科技 版权所有',
              style: TextStyle(fontSize: 12.sp, color: AppColors.textHint),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(IconData icon, String title, VoidCallback? onTap, {Widget? trailing}) {
    return ListTile(
      leading: Icon(icon, color: AppColors.textSecondary),
      title: Text(title, style: TextStyle(fontSize: 15.sp, color: AppColors.textPrimary)),
      trailing: trailing ?? const Icon(Icons.chevron_right, color: AppColors.textHint),
      onTap: onTap,
    );
  }
}
