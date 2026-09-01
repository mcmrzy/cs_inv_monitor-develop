import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/entities/organization.dart';

typedef SendOrganizationInvitation = Future<Map<String, dynamic>> Function({
  required String email,
  required String roleCode,
  required int expiresHours,
});

class OrgInvitationDialogResult {
  final String email;
  final Map<String, dynamic> response;

  const OrgInvitationDialogResult({
    required this.email,
    required this.response,
  });
}

/// Stateful bottom-sheet content that owns its input controllers and prevents
/// repeated invitation requests while the first request is still running.
class OrgInvitationDialog extends StatefulWidget {
  final List<String> allowedRoles;
  final String initialRole;
  final SendOrganizationInvitation onSubmit;

  const OrgInvitationDialog({
    super.key,
    required this.allowedRoles,
    required this.initialRole,
    required this.onSubmit,
  });

  @override
  State<OrgInvitationDialog> createState() => _OrgInvitationDialogState();
}

class _OrgInvitationDialogState extends State<OrgInvitationDialog> {
  late final TextEditingController _emailController;
  late final TextEditingController _daysController;
  late String _roleCode;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController();
    _daysController = TextEditingController(text: '7');
    _roleCode = widget.initialRole;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _daysController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;

    final email = _emailController.text.trim();
    final days = int.tryParse(_daysController.text) ?? 7;
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入邮箱地址')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final response = await widget.onSubmit(
        email: email,
        roleCode: _roleCode,
        expiresHours: days * 24,
      );
      if (!mounted) return;
      Navigator.pop(
        context,
        OrgInvitationDialogResult(email: email, response: response),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发送失败：$error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isSubmitting,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(24.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '发送邀请',
                    style: TextStyle(
                      fontSize: 20.sp,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed:
                        _isSubmitting ? null : () => Navigator.pop(context),
                  ),
                ],
              ),
              SizedBox(height: 24.h),
              TextField(
                controller: _emailController,
                enabled: !_isSubmitting,
                decoration: const InputDecoration(
                  labelText: '邮箱地址',
                  hintText: '请输入邀请对象的邮箱',
                  prefixIcon: Icon(Icons.email),
                ),
                textInputAction: TextInputAction.next,
              ),
              SizedBox(height: 16.h),
              DropdownButtonFormField<String>(
                initialValue: _roleCode,
                decoration: const InputDecoration(
                  labelText: '成员角色',
                  prefixIcon: Icon(Icons.badge),
                ),
                items: OrgMemberRole.values
                    .where((role) => widget.allowedRoles.contains(role.apiValue))
                    .map(
                      (role) => DropdownMenuItem(
                        value: role.apiValue,
                        child: Text(role.displayName),
                      ),
                    )
                    .toList(),
                onChanged: _isSubmitting
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _roleCode = value);
                        }
                      },
              ),
              SizedBox(height: 16.h),
              TextField(
                controller: _daysController,
                enabled: !_isSubmitting,
                decoration: const InputDecoration(
                  labelText: '有效期（天）',
                  hintText: '默认 7 天',
                  prefixIcon: Icon(Icons.calendar_today),
                ),
                keyboardType: TextInputType.number,
              ),
              SizedBox(height: 24.h),
              FilledButton(
                onPressed: _isSubmitting ? null : _submit,
                child: _isSubmitting
                    ? SizedBox.square(
                        dimension: 18.w,
                        child: const CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('发送邀请'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
