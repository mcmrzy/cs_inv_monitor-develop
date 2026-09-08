import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/stores/organization_context_store.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 组织选择对话框
/// 用于在多个组织之间切换
class OrgSelectorDialog extends StatefulWidget {
  const OrgSelectorDialog({super.key});

  @override
  State<OrgSelectorDialog> createState() => _OrgSelectorDialogState();
}

class _OrgSelectorDialogState extends State<OrgSelectorDialog> {
  OrganizationContextStore? _orgStore;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _orgStore = context.read<OrganizationContextStore>();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _orgStore!,
      builder: (context, _) {
        final theme = Theme.of(context);
        final l10n = AppLocalizations.of(context)!;
        final orgs = _orgStore!.availableOrgs;

        if (_orgStore!.isLoading) {
          return AlertDialog(
            content: Row(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(width: 16),
                Text(l10n.loading),
              ],
            ),
          );
        }

        if (orgs.isEmpty) {
          return AlertDialog(
            title: Text(l10n.str('org_hint')),
            content: Text(l10n.str('org_not_in_any')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.confirm),
              ),
            ],
          );
        }

        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.groups, color: theme.colorScheme.primary),
              SizedBox(width: 8.w),
              Text(l10n.str('org_switch_title')),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: orgs.map((org) {
                final isActive = _orgStore!.activeOrgId == org.id;
                return ListTile(
                  leading: Stack(
                    children: [
                      Container(
                        width: 40.w,
                        height: 40.w,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20.r),
                        ),
                        child: Icon(
                          Icons.business,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      if (isActive)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 16.w,
                            height: 16.w,
                            decoration: BoxDecoration(
                              color: AppColors.success,
                              shape: BoxShape.circle,
                              border: Border.fromBorderSide(
                                BorderSide(
                                  color: theme.colorScheme.surface,
                                  width: 2,
                                ),
                              ),
                            ),
                            child: const Icon(
                              Icons.check,
                              size: 10,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                  title: Text(
                    org.name,
                    style: TextStyle(
                      fontWeight:
                          isActive ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.str('org_member_device_count', {
                          'members': '${org.memberCount}',
                          'devices': '${org.deviceCount}',
                        }),
                      ),
                      if (org.description != null &&
                          org.description!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            org.description!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.sp,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                  trailing: isActive
                      ? Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8.w,
                            vertical: 4.h,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                          child: Text(
                            l10n.str('org_current'),
                            style: TextStyle(
                              fontSize: 12.sp,
                              color: AppColors.success,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                      : null,
                  onTap: () async {
                    try {
                      await _orgStore!.switchContextToOrganization(
                        org.id,
                        org.name,
                        context.read<AuthBloc>(),
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            l10n.str('org_switched_to', {
                              'name': org.name,
                            }),
                          ),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                      Navigator.pop(context, true);
                    } catch (error) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            l10n.str('org_switch_failed', {
                              'error': error.toString(),
                            }),
                          ),
                        ),
                      );
                    }
                  },
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.cancel),
            ),
          ],
        );
      },
    );
  }
}

/// 显示组织选择对话框的便捷函数
Future<bool?> showOrgSelectorDialog(BuildContext context) async {
  return await showDialog<bool>(
    context: context,
    builder: (context) => const OrgSelectorDialog(),
  );
}
