import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:inv_app/core/auth/permission_codes.dart';
import 'package:inv_app/core/components/permission_gate.dart';
import 'package:inv_app/core/config/app_config.dart';
import 'package:inv_app/core/entities/organization.dart';
import 'package:inv_app/core/stores/organization_context_store.dart';
import 'package:inv_app/core/services/api_service.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/widgets/org_invitation_dialog.dart';
import 'package:intl/intl.dart';
import 'package:inv_app/core/widgets/skeleton_widgets.dart';

/// 可邀请角色按邀请人所属组织类型受限（与后端 inviterAllowedRolesByOrgType 一致）：
/// manufacturer→{agent,distributor,installer,customer}、agent→{installer,customer}、
/// distributor→{installer,customer}、installer→{customer}、customer→不可邀请；
/// org_admin 为管理角色，始终可分配。
const Map<String, List<String>> kAllowedRolesByOrgType = {
  'manufacturer': ['agent', 'distributor', 'installer', 'customer'],
  'agent': ['installer', 'customer'],
  'distributor': ['installer', 'customer'],
  'installer': ['customer'],
  'customer': [],
};

/// 多组织取并集；org_admin 始终可分配。
List<String> resolveAllowedRoles(Set<String> orgTypes) {
  final allowed = <String>{'org_admin'};
  for (final t in orgTypes) {
    allowed.addAll(kAllowedRolesByOrgType[t] ?? const []);
  }
  return allowed.toList();
}

/// 组织邀请管理屏幕
class OrgInvitationScreen extends StatefulWidget {
  final int organizationId;

  const OrgInvitationScreen({
    super.key,
    required this.organizationId,
  });

  @override
  State<OrgInvitationScreen> createState() => _OrgInvitationScreenState();
}

class _OrgInvitationScreenState extends State<OrgInvitationScreen>
    with SingleTickerProviderStateMixin {
  late ApiService _apiService;
  late TabController _tabController;
  List<OrganizationInvitation>? _invitations;
  bool _isLoading = false;
  String? _error;
  Set<String> _myOrgTypes = {};
  bool _orgTypesLoaded = false;

  @override
  void initState() {
    super.initState();
    _apiService = context.read<OrganizationContextStore>().apiService;
    _tabController = TabController(length: 3, vsync: this);

    _loadInvitations();
    _loadMyOrgTypes();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadInvitations() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final invitations =
          await _apiService.listInvitations(widget.organizationId);

      if (mounted) {
        setState(() {
          _invitations = invitations;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  List<OrganizationInvitation> get _pendingInvitations {
    return _invitations?.where((i) => i.status == 'pending').toList() ?? [];
  }

  List<OrganizationInvitation> get _acceptedInvitations {
    return _invitations?.where((i) => i.status == 'accepted').toList() ?? [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.mail),
            SizedBox(width: 8),
            Text('邀请管理'),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '待接受'),
            Tab(text: '已接受'),
            Tab(text: '全部'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadInvitations,
            tooltip: '刷新',
          ),
          PermissionGate(
            permissionCode: PermissionCodes.organizationsInvite,
            requiredOrgId: widget.organizationId,
            child: IconButton(
              icon: const Icon(Icons.add),
              onPressed: _showSendInviteDialog,
              tooltip: '发送邀请',
            ),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildInvitationList(_pendingInvitations),
          _buildInvitationList(_acceptedInvitations),
          _buildInvitationList(_invitations ?? []),
        ],
      ),
      floatingActionButton: PermissionGate(
        permissionCode: PermissionCodes.organizationsInvite,
        requiredOrgId: widget.organizationId,
        child: FloatingActionButton.extended(
          onPressed: _showSendInviteDialog,
          icon: const Icon(Icons.person_add),
          label: const Text('发送邀请'),
        ),
      ),
    );
  }

  Widget _buildInvitationList(List<OrganizationInvitation> invitations) {
    if (_isLoading) {
      return const PageSkeleton();
    }

    if (_error != null) {
      final theme = Theme.of(context);
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64.w,
              color: theme.colorScheme.outlineVariant,
            ),
            SizedBox(height: 16.h),
            Text('加载失败：$_error'),
            SizedBox(height: 16.h),
            ElevatedButton.icon(
              onPressed: _loadInvitations,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (invitations.isEmpty) {
      final theme = Theme.of(context);
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 64.w,
              color: theme.colorScheme.outlineVariant,
            ),
            SizedBox(height: 16.h),
            Text(
              '暂无邀请数据',
              style: TextStyle(
                fontSize: 18.sp,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.all(16.w),
      itemCount: invitations.length,
      separatorBuilder: (context, index) => SizedBox(height: 12.h),
      itemBuilder: (context, index) {
        final invite = invitations[index];
        return _InvitationCard(
          invitation: invite,
          onRevoke: invite.status == 'pending'
              ? () => _revokeInvitation(invite.id)
              : null,
        );
      },
    );
  }

  /// 加载当前用户所属组织类型（决定可邀请角色集合）
  Future<void> _loadMyOrgTypes() async {
    try {
      final result = await _apiService.get<List<dynamic>>(
        '/my/organizations',
        fromJson: (data) => data as List,
      );
      final orgTypes = result.fold(
        (failure) => <String>{},
        (list) => list
            .map((e) => (e as Map)['type']?.toString() ?? '')
            .where((t) => t.isNotEmpty)
            .toSet(),
      );
      if (mounted) {
        setState(() {
          _myOrgTypes = orgTypes;
          _orgTypesLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _orgTypesLoaded = true);
      }
    }
  }

  Future<void> _showSendInviteDialog() async {
    // 确保角色集合已加载（后端会再次校验，这里保证下拉选项正确）
    if (!_orgTypesLoaded) {
      await _loadMyOrgTypes();
    }
    if (!mounted) return;
    final allowedRoles = resolveAllowedRoles(_myOrgTypes);
    // 默认选中第一个可邀请的渠道角色（避免默认角色不在允许集合中）
    final defaultRole = allowedRoles.length > 1
        ? allowedRoles.firstWhere((r) => r != 'org_admin', orElse: () => 'org_admin')
        : 'org_admin';
    final dialogResult = await showModalBottomSheet<OrgInvitationDialogResult>(
      context: context,
      isScrollControlled: true,
      builder: (context) => OrgInvitationDialog(
        allowedRoles: allowedRoles,
        initialRole: defaultRole,
        onSubmit: ({
          required String email,
          required String roleCode,
          required int expiresHours,
        }) =>
            _apiService.sendInvitation(
          orgId: widget.organizationId,
          email: email,
          roleCode: roleCode,
          expiresHours: expiresHours,
        ),
      ),
    );

    if (!mounted || dialogResult == null) return;

    // 提取创建时唯一返回的邀请链接（相对路径）
    String? inviteLink;
    final results = dialogResult.response['results'];
    if (results is List && results.isNotEmpty) {
      final first = results.first;
      if (first is Map && first['invite_link'] != null) {
        inviteLink = first['invite_link'] as String;
      }
    }

    if (inviteLink != null) {
      // 邀请链接指向管理后台（Web），使用 frontendBaseUrl（www 域）
      _showInviteLinkDialog(
        '${AppConfig.frontendBaseUrl}$inviteLink',
        dialogResult.email,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('邀请已发送（邀请链接仅在创建时可见）'),
        ),
      );
    }

    // 刷新邀请列表
    _loadInvitations();
  }

  Future<void> _revokeInvitation(int invitationId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认撤销'),
        content: const Text('确定要撤销此邀请吗？该邀请链接将失效。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('撤销'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _apiService.revokeInvitation(invitationId);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('邀请已撤销'),
            ),
          );

          _loadInvitations();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('撤销失败：$e'),
            ),
          );
        }
      }
    }
  }

  /// 展示创建时返回的邀请链接（完整链接仅此一次可见）
  void _showInviteLinkDialog(String link, String email) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('邀请已发送'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('已向 $email 发送邀请。'),
            SizedBox(height: 12.h),
            const Text('邀请链接仅此一次可见，请及时分享给受邀人：'),
            SizedBox(height: 8.h),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: SelectableText(
                link,
                style: TextStyle(fontSize: 13.sp),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}

/// 邀请卡片组件
class _InvitationCard extends StatelessWidget {
  final OrganizationInvitation invitation;
  final VoidCallback? onRevoke;

  const _InvitationCard({
    required this.invitation,
    this.onRevoke,
  });

  /// 状态 → (颜色, 文案)，对齐后端 status 枚举
  (Color, String) _statusDisplay(String status) {
    switch (status) {
      case 'accepted':
        return (Colors.green, '已接受');
      case 'rejected':
        return (Colors.red, '已拒绝');
      case 'expired':
        return (AppColors.textHint, '已过期');
      case 'revoked':
        return (AppColors.textHint, '已撤销');
      case 'pending':
      default:
        return (Colors.orange, '待接受');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (statusColor, statusText) = _statusDisplay(invitation.status);
    final roleText = invitation.roleCodes.isEmpty
        ? '未指定'
        : invitation.roleCodes
            .map((c) => OrgMemberRoleExtension.fromApiValue(c).displayName)
            .join('、');

    return Card(
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8.w,
                        height: 8.w,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Text(
                        statusText,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (onRevoke != null)
                  IconButton(
                    icon: const Icon(
                      Icons.cancel_outlined,
                      color: Colors.red,
                    ),
                    tooltip: '撤销邀请',
                    onPressed: onRevoke,
                  ),
              ],
            ),
            Divider(height: 24.h),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invitation.email,
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  '角色：$roleText',
                  style: TextStyle(
                    fontSize: 14.sp,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (invitation.organization != null) ...[
                  SizedBox(height: 4.h),
                  Text(
                    '组织：${invitation.organization}',
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (invitation.inviterName != null) ...[
                  SizedBox(height: 4.h),
                  Text(
                    '邀请人：${invitation.inviterName}',
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
            if (invitation.expiresAt != null) ...[
              Divider(height: 24.h),
              Row(
                children: [
                  Icon(
                    Icons.access_time,
                    size: 16.sp,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  SizedBox(width: 8.w),
                  Text(
                    '有效期至：${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.parse(invitation.expiresAt!))}',
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: theme.colorScheme.onSurfaceVariant,
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
}
