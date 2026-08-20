import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/widgets/app_toast.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// BLE 绑定 PIN 输入对话框（设备直连设置页 / 添加设备页共用）。
///
/// 以独立 [StatefulWidget] 持有 [TextEditingController]，并在自身 dispose 中释放，
/// 避免旧的实现方式在 showDialog(...) 返回后立即 dispose controller——
/// 对话框路由的退场动画仍在运行，期间框架会再次对 controller 注册监听，
/// 从而触发 “A TextEditingController was used after being disposed”
/// 崩溃，并级联出 “dirty widget in the wrong build scope / Duplicate GlobalKeys /
/// _dependents.isEmpty” 等一系列树损坏异常。
///
/// 返回用户输入的 6 位铭牌 PIN（String），取消返回 null。
Future<String?> showBlePinBindDialog({
  required BuildContext context,
  required String deviceSn,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _BlePinBindDialog(deviceSn: deviceSn),
  );
}

class _BlePinBindDialog extends StatefulWidget {
  final String deviceSn;

  const _BlePinBindDialog({required this.deviceSn});

  @override
  State<_BlePinBindDialog> createState() => _BlePinBindDialogState();
}

class _BlePinBindDialogState extends State<_BlePinBindDialog> {
  final _pinController = TextEditingController();

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  void _submit() {
    final pin = _pinController.text.trim();
    if (pin.length != 6) {
      AppToast.show(context, AppLocalizations.of(context)!.pinLengthError,
          type: ToastType.info);
      return;
    }
    Navigator.pop(context, pin);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.str('ble_bind_confirm_title')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.str('ble_bind_confirm_desc')),
          SizedBox(height: 8.h),
          Text(
            widget.deviceSn,
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w600,
              color: AppColor.textPrimary(context),
            ),
          ),
          SizedBox(height: 16.h),
          TextField(
            controller: _pinController,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: l10n.pinInputTitle,
              hintText: l10n.pinInputHint,
              counterText: '',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(l10n.pinInputConfirm),
        ),
      ],
    );
  }
}
