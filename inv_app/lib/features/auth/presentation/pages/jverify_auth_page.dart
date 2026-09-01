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
        // 取号类错误给出具体原因（运营商通道/SIM 卡问题），SDK 未就绪与其它错误走对应通用文案
        if (e.code == 2002 ||
            e.code == 2003 ||
            e.code == 2004 ||
            e.code == 2005) {
          _failReason = _l10n?.jverifyCarrierUnavailable ??
              '运营商取号失败，请确认 SIM 卡可用且开启移动数据后重试';
        } else if (e.code == 6012) {
          _failReason =
              _l10n?.jverifyInitFailed ?? '认证服务初始化失败，请使用其他方式登录';
        } else {
          _failReason =
              _l10n?.jverifyAuthFailed ?? '一键登录失败，请使用其他方式登录';
        }
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
              } else if (state is AuthError &&
                  state is! AuthCodeSendError) {
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

  /// 拉起授权页前的过渡态：品牌吉祥物徽章 + loading + 安全提示
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
            // 品牌吉祥物圆形徽章（小烁欢迎姿态）
            Container(
              width: 76.w,
              height: 76.w,
              padding: EdgeInsets.all(6.w),
              decoration: BoxDecoration(
                color: AppColor.surfaceContainer(context).withValues(alpha: 0.92),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(32.r),
                child: Image.asset(
                  CsergyAssets.xiaoshuoWelcome,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Icon(
                    Icons.bolt_rounded,
                    size: 36.w,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
            SizedBox(height: 20.h),
            SizedBox(
              width: 26.w,
              height: 26.w,
              child: const CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
            SizedBox(height: 14.h),
            Text(
              l10n?.jverifyLaunching ?? '正在拉起运营商认证...',
              style: TextStyle(
                fontSize: 14.sp,
                color: AppColor.textPrimary(context),
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 6.h),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 48.w),
              child: Text(
                l10n?.jverifySecureTip ??
                    '运营商安全认证 · 本机号码一键登录',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.sp, color: AppColor.textHint(context)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 取消/失败后的兜底视图：原因卡片 + 渐变胶囊重试 + 其他方式登录
  /// 内容置于底部浅色区，保证文字/按钮对比度
  Widget _buildFailed(AuthState state) {
    final l10n = _l10n;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.fromLTRB(24.w, 0, 24.w, 60.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 失败原因卡片：白底圆角 + 图标 + 提示
            Container(
              padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 18.h),
              decoration: BoxDecoration(
                color: AppColor.surfaceContainer(context)
                    .withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(20.r),
                border: Border.all(
                  color: AppColor.outline(context).withValues(alpha: 0.4),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 品牌吉祥物徽章（失败场景用离线/提醒姿态兜底）
                  Container(
                    width: 56.w,
                    height: 56.w,
                    padding: EdgeInsets.all(4.w),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.06),
                      shape: BoxShape.circle,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24.r),
                      child: Image.asset(
                        CsergyAssets.xiaoshuoReminder,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Icon(
                          Icons.smartphone_rounded,
                          size: 28.w,
                          color: AppColors.error,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 12.h),
                  Text(
                    _failReason,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15.sp,
                      color: AppColor.textPrimary(context),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 6.h),
                  Text(
                    l10n?.jverifySecureTip ??
                        '运营商安全认证 · 本机号码一键登录',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: AppColor.textHint(context),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 20.h),
            // 品牌渐变胶囊重试按钮
            SizedBox(
              height: 50.h,
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(25.r),
                child: Ink(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF1565C0), Color(0xFF2196F3)],
                    ),
                    borderRadius: BorderRadius.circular(25.r),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF1565C0)
                            .withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(25.r),
                    onTap: state is AuthLoading ? null : _startAuth,
                    child: Center(
                      child: state is AuthLoading
                          ? SizedBox(
                              width: 20.w,
                              height: 20.w,
                              child: const CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              l10n?.jverifyRetry ?? '重试',
                              style: TextStyle(
                                fontSize: 16.sp,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
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
