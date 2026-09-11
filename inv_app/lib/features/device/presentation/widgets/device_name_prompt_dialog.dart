import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:fpdart/fpdart.dart' hide State;

import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/features/device/data/device_name_prompt_storage.dart';
import 'package:inv_app/features/device/domain/repositories/device_repository.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 绑定成功后的一次性「设置设备名称」引导。
///
/// 名称是选填的：用户点「暂不设置」后把该 SN 记进 [DeviceNamePromptStorage]，
/// 之后不再为这台设备弹引导；名称随时可在 设备列表长按 → 编辑 中修改。
/// 保存成功后返回 true。
class DeviceNamePromptDialog extends StatefulWidget {
  final String sn;
  final DeviceRepository repository;
  final DeviceNamePromptStorage storage;

  const DeviceNamePromptDialog({
    required this.sn,
    required this.repository,
    required this.storage,
    super.key,
  });

  /// 按需弹出引导；该设备被忽略过时直接返回 false（不弹窗）。
  static Future<bool> showIfNeeded(
    BuildContext context, {
    required String sn,
    required DeviceRepository repository,
    DeviceNamePromptStorage? storage,
  }) async {
    final promptStorage = storage ?? DeviceNamePromptStorage();
    if (sn.trim().isEmpty) return false;
    if (await promptStorage.isSkipped(sn)) return false;
    if (!context.mounted) return false;

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DeviceNamePromptDialog(
        sn: sn,
        repository: repository,
        storage: promptStorage,
      ),
    );
    return saved ?? false;
  }

  @override
  State<DeviceNamePromptDialog> createState() => _DeviceNamePromptDialogState();
}

class _DeviceNamePromptDialogState extends State<DeviceNamePromptDialog> {
  final _controller = TextEditingController();
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 留空等同跳过：同样记住这台设备不再提示
  Future<void> _save() async {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      await _skip();
      return;
    }
    if (_isSubmitting) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final result = await widget.repository.updateDevice(widget.sn, alias: name);
    if (!mounted) return;

    switch (result) {
      case Left(value: final failure):
        setState(() {
          _isSubmitting = false;
          _errorMessage = AppLocalizations.of(context)!.translateError(
            failure.message,
          );
        });
      case Right():
        Navigator.of(context).pop(true);
    }
  }

  Future<void> _skip() async {
    if (_isSubmitting) return;
    await widget.storage.markSkipped(widget.sn);
    if (!mounted) return;
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PopScope(
      canPop: !_isSubmitting,
      child: AlertDialog(
        title: Text(l10n.str('device_name_prompt_title')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.str('device_name_prompt_desc'),
                style: TextStyle(
                  fontSize: 13.sp,
                  height: 1.5,
                  color: AppColor.textSecondary(context),
                ),
              ),
              SizedBox(height: 16.h),
              TextField(
                controller: _controller,
                enabled: !_isSubmitting,
                maxLength: 50,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: l10n.deviceAlias,
                  hintText: l10n.deviceAliasHint,
                  counterText: '',
                  prefixIcon: Icon(Icons.badge_outlined, size: 20.sp),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                ),
              ),
              if (_errorMessage != null) ...[
                SizedBox(height: 8.h),
                Text(
                  _errorMessage!,
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
              SizedBox(height: 12.h),
              Text(
                l10n.str('device_name_prompt_hint'),
                style: TextStyle(
                  fontSize: 12.sp,
                  height: 1.4,
                  color: AppColor.textHint(context),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isSubmitting ? null : _skip,
            child: Text(l10n.str('device_name_prompt_skip')),
          ),
          FilledButton(
            onPressed: _isSubmitting ? null : _save,
            child: _isSubmitting
                ? SizedBox(
                    width: 18.w,
                    height: 18.w,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(l10n.save),
          ),
        ],
      ),
    );
  }
}
