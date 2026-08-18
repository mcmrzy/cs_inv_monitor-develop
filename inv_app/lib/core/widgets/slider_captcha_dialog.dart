import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:inv_app/core/services/captcha_service.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 弹出滑块拼图验证对话框
///
/// 返回验证通过后的 verifyToken（10 分钟有效），
/// 用户取消或关闭时返回 null。
Future<String?> showSliderCaptcha(BuildContext context) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const SliderCaptchaDialog(),
  );
}

/// 滑块拼图验证对话框
///
/// 对接后端 /captcha/generate + /captcha/verify：
/// 展示背景图与拼图块，用户拖动滑块将拼图块对齐缺口，
/// 校验通过后返回 verifyToken 供发送验证码接口携带。
class SliderCaptchaDialog extends StatefulWidget {
  const SliderCaptchaDialog({super.key});

  @override
  State<SliderCaptchaDialog> createState() => _SliderCaptchaDialogState();
}

class _SliderCaptchaDialogState extends State<SliderCaptchaDialog> {
  static const double _imageWidth = 320;
  static const double _pieceWidth = 60;
  static const double _thumbSize = 44;

  final CaptchaService _captchaService = GetIt.instance<CaptchaService>();

  CaptchaChallenge? _challenge;
  bool _loading = true;
  bool _verifying = false;
  String? _error;

  double _thumbDx = 0;
  double _trackMax = 0;
  DateTime? _dragStartAt;

  @override
  void initState() {
    super.initState();
    _loadChallenge();
  }

  Future<void> _loadChallenge() async {
    setState(() {
      _loading = true;
      _error = null;
      _thumbDx = 0;
      _dragStartAt = null;
    });
    try {
      final challenge = await _captchaService.generate();
      if (!mounted) return;
      setState(() {
        _challenge = challenge;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AppLocalizations.of(context)!.sliderCaptchaFailed;
      });
    }
  }

  Future<void> _submit(double imageX, int durationMs) async {
    final challenge = _challenge;
    if (challenge == null || _verifying) return;
    setState(() => _verifying = true);
    try {
      final token = await _captchaService.verify(
        challengeId: challenge.challengeId,
        x: imageX,
        duration: durationMs,
      );
      if (!mounted) return;
      Navigator.of(context).pop(token);
    } catch (e) {
      if (!mounted) return;
      // 校验失败：挑战已被服务端消费，需重新生成
      setState(() {
        _verifying = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
      await _loadChallenge();
    }
  }

  void _onPanStart(DragStartDetails details, double trackMax) {
    if (_verifying || _challenge == null) return;
    _dragStartAt = DateTime.now();
    _updateThumb(details.localPosition.dx, trackMax);
  }

  void _onPanUpdate(DragUpdateDetails details, double trackMax) {
    if (_verifying || _dragStartAt == null) return;
    _updateThumb(details.localPosition.dx, trackMax);
  }

  void _onPanEnd(double scale) {
    if (_verifying || _dragStartAt == null) return;
    final durationMs = DateTime.now().difference(_dragStartAt!).inMilliseconds;
    final imageX = _thumbDx / scale;
    _submit(imageX, durationMs);
  }

  void _updateThumb(double localX, double trackMax) {
    final dx = (localX - _thumbSize / 2).clamp(0.0, trackMax);
    setState(() => _thumbDx = dx);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.sliderCaptchaTitle,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              l10n.sliderCaptchaHint,
              style: TextStyle(
                fontSize: 13,
                color: AppColor.textSecondary(context),
              ),
            ),
            const SizedBox(height: 12),
            _buildImageArea(),
            const SizedBox(height: 12),
            _buildSliderTrack(),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 16,
                    color: Colors.red,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.red,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 背景图 + 拼图块区域（原图 320x160，按可用宽度等比缩放）
  Widget _buildImageArea() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final scale = width / _imageWidth;
        final challenge = _challenge;
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: width,
            height: width / 2,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_loading || challenge == null)
                  Container(
                    color: AppColor.surfaceHover(context),
                    child: const Center(child: CircularProgressIndicator()),
                  )
                else ...[
                  Image.memory(
                    base64Decode(challenge.bgImage),
                    fit: BoxFit.fill,
                    gaplessPlayback: true,
                  ),
                  Positioned(
                    left: _pieceLeft(width),
                    top: 0,
                    bottom: 0,
                    child: Image.memory(
                      base64Decode(challenge.puzzleImage),
                      width: _pieceWidth * scale,
                      fit: BoxFit.fill,
                      gaplessPlayback: true,
                    ),
                  ),
                ],
                Positioned(
                  right: 6,
                  top: 6,
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: _loading ? null : _loadChallenge,
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(
                          Icons.refresh,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 拼图块显示位置：与滑块等比映射到图片宽度，且不超出右边界
  double _pieceLeft(double imageDisplayWidth) {
    if (_trackMax <= 0) return 0;
    final scale = imageDisplayWidth / _imageWidth;
    final maxLeft = imageDisplayWidth - _pieceWidth * scale;
    final left = _thumbDx * (imageDisplayWidth / (_trackMax + _thumbSize));
    return left.clamp(0.0, maxLeft);
  }

  /// 底部滑块轨道
  Widget _buildSliderTrack() {
    final l10n = AppLocalizations.of(context)!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final trackMax = constraints.maxWidth - _thumbSize;
        // 轨道尺寸变化（如旋屏）时收敛滑块位置
        if (_trackMax != trackMax) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _thumbDx > trackMax) {
              setState(() => _thumbDx = trackMax);
            }
          });
        }
        _trackMax = trackMax;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (details) => _onPanStart(details, trackMax),
          onPanUpdate: (details) => _onPanUpdate(details, trackMax),
          onPanEnd: (_) =>
              _onPanEnd(constraints.maxWidth / _imageWidth),
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              color: AppColor.surfaceHover(context),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Stack(
              children: [
                // 已拖动进度条
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: _thumbDx + _thumbSize,
                        color: AppColors.primary.withValues(alpha: 0.15),
                      ),
                    ),
                  ),
                ),
                // 提示文字
                Center(
                  child: _verifying
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        )
                      : Text(
                          l10n.sliderCaptchaHint,
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColor.textHint(context),
                          ),
                        ),
                ),
                // 滑块按钮
                Positioned(
                  left: _thumbDx,
                  top: 2,
                  bottom: 2,
                  child: Container(
                    width: _thumbSize,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.35),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.double_arrow,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
