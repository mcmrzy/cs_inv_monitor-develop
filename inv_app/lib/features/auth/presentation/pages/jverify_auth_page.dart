import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:inv_app/core/services/jverify_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/theme/csergy_assets.dart';
import 'package:inv_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 一键登录授权页宿主
///
/// 无自绘登录 UI：进入后自动拉起极光自绘授权页
/// （品牌区 + 脱敏手机号 138****1234 + "同意并登录"）。
/// 成功直接进 /home；取消/失败展示极简失败视图，可重试或使用其他方式登录。
class JVerifyAuthPage extends StatefulWidget {
  const JVerifyAuthPage({super.key});

  @override
  State<JVerifyAuthPage> createState() => _JVerifyAuthPageState();
}

enum _AuthStage { launching, failed }

class _JVerifyAuthPageState extends State<JVerifyAuthPage> {
  _AuthStage _stage = _AuthStage.launching;
  String _failReason = '';

  AppLocalizations? get _l10n => AppLocalizations.of(context);

  @override
  void initState() {
    super.initState();
    _startAuth();
  }

  /// 拉起自绘授权页；结果由 BlocConsumer 与 [JVerifyService.loginAuth] 处理
  Future<void> _startAuth() async {
    setState(() {
      _stage = _AuthStage.launching;
      _failReason = '';
    });

    try {
      final jverifyService = getIt<JVerifyService>();
      final result = await jverifyService.loginAuth();

      if (!mounted) return;

      final accessCode = result?['accessCode'];
      if (accessCode == null || accessCode.isEmpty) {
        // 用户取消（8001/9000）或 SDK 未返回 accessCode
        setState(() {
          _stage = _AuthStage.failed;
          _failReason = _l10n?.jverifyCancelled ?? '已取消一键登录';
        });
        return;
      }

      // 直接调用后端登录（授权页已关闭），loading 保持到 Bloc 结果
      context
          .read<AuthBloc>()
          .add(AuthJVerifyLoginWithTokenRequested(loginToken: accessCode));
    } on JVerifyCarrierException catch (e) {
      debugPrint('[JVerifyAuthPage] carrier error: ${e.code} - ${e.message}');
      if (!mounted) return;
      setState(() {
        _stage = _AuthStage.failed;
        _failReason = _l10n?.jverifyAuthFailed ?? '一键登录失败，请使用其他方式登录';
      });
    } catch (e) {
      debugPrint('[JVerifyAuthPage] unexpected error: $e');
      if (!mounted) return;
      setState(() {
        _stage = _AuthStage.failed;
        _failReason = _l10n?.jverifyAuthFailed ?? '一键登录失败，请使用其他方式登录';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColor.surfaceContainer(context),
      body: Stack(
        children: [
          // 一键登录背景图（品牌深蓝科技渐变，铺满；底部浅色区放操作内容）
          Positioned.fill(
            child: IgnorePointer(
              child: Image.asset(
                CsergyAssets.bgJverify,
                fit: BoxFit.cover,
              ),
            ),
          ),
          BlocConsumer<AuthBloc, AuthState>(
            listener: (context, state) {
              if (state is AuthAuthenticated) {
                debugPrint('[JVerifyAuthPage] Login success, navigate to /home');
                context.go('/home');
              } else if (state is AuthError) {
                // 后端登录失败：切失败视图
                if (mounted) {
                  setState(() {
                    _stage = _AuthStage.failed;
                    _failReason =
                        AppLocalizations.of(context)!.translateError(state.message);
                  });
                }
              }
            },
            builder: (context, state) {
              return SafeArea(
                child: _stage == _AuthStage.launching
                    ? _buildLaunching()
                    : _buildFailed(state),
              );
            },
          ),
        ],
      ),
    );
  }

  /// 拉起授权页前的过渡态：loading + 提示
  /// 内容置于底部浅色区，避开深色渐变区
  Widget _buildLaunching() {
    final l10n = _l10n;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.only(bottom: 72.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
            SizedBox(height: 14.h),
            Text(
              l10n?.jverifyLaunching ?? '正在拉起运营商认证...',
              style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  /// 取消/失败后的极简兜底视图：可重试或使用其他方式登录
  /// 内容置于底部浅色区，保证文字/按钮对比度
  Widget _buildFailed(AuthState state) {
    final l10n = _l10n;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.fromLTRB(48.w, 0, 48.w, 72.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _failReason,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15.sp, color: AppColors.textPrimary),
            ),
            SizedBox(height: 28.h),
            SizedBox(
              height: 48.h,
              child: ElevatedButton(
                onPressed: state is AuthLoading ? null : _startAuth,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.surfaceHover,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14.r),
                  ),
                ),
                child: Text(
                  l10n?.jverifyRetry ?? '重试',
                  style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            SizedBox(height: 12.h),
            TextButton(
              onPressed: state is AuthLoading
                  ? null
                  : () => context.go('/login'),
              child: Text(
                l10n?.useOtherLogin ?? '使用其他方式登录',
                style: TextStyle(fontSize: 14.sp, color: AppColors.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
