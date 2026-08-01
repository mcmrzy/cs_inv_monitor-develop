import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:inv_app/core/components/permission_gate.dart';
import 'package:inv_app/core/config/app_config.dart';
import 'package:inv_app/core/entities/organization.dart';
import 'package:inv_app/core/stores/organization_context_store.dart';
import 'package:inv_app/core/services/api_service.dart';
import 'package:intl/intl.dart';

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
            resource: 'organization',
            action: 'manage',
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
        resource: 'organization',
        action: 'manage',
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
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('加载失败：$_error'),
            const SizedBox(height: 16),
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
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              '暂无邀请数据',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: invitations.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
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
        '/api/v1/my/organizations',
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
    final emailController = TextEditingController();
    final roleController = TextEditingController(text: defaultRole);
    final daysController = TextEditingController(text: '7');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '发送邀请',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: emailController,
                      decoration: InputDecoration(
                        labelText: '邮箱地址',
                        hintText: '请输入邀请对象的邮箱',
                        prefixIcon: const Icon(Icons.email),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: roleController.text,
                      decoration: InputDecoration(
                        labelText: '成员角色',
                        prefixIcon: const Icon(Icons.badge),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      items: OrgMemberRole.values
                          .where((r) => allowedRoles.contains(r.apiValue))
                          .map(
                            (r) => DropdownMenuItem(
                              value: r.apiValue,
                              child: Text(r.displayName),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setModalState(() {
                          roleController.text = value!;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: daysController,
                      decoration: InputDecoration(
                        labelText: '有效期（天）',
                        hintText: '默认 7 天',
                        prefixIcon: const Icon(Icons.calendar_today),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () async {
                        final email = emailController.text.trim();
                        final days = int.tryParse(daysController.text) ?? 7;

                        if (email.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('请输入邮箱地址')),
                          );
                          return;
                        }

                        try {
                          final result = await _apiService.sendInvitation(
                            orgId: widget.organizationId,
                            email: email,
                            roleCode: roleController.text,
                            expiresHours: days * 24,
                          );

                          // 提取创建时唯一返回的邀请链接（相对路径）
                          String? inviteLink;
                          final results = result['results'];
                          if (results is List && results.isNotEmpty) {
                            final first = results.first;
                            if (first is Map && first['invite_link'] != null) {
                              inviteLink = first['invite_link'] as String;
                            }
                          }

                          await Future.microtask(() {});
                          if (!mounted) return;
                          Navigator.pop(context); // ignore: use_build_context_synchronously
                          if (inviteLink != null) {
                            final serverBase =
                                AppConfig.apiBaseUrl.replaceAll(
                              RegExp(r'/api/v1$'),
                              '',
                            );
                            _showInviteLinkDialog(
                              '$serverBase$inviteLink',
                              email,
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar( // ignore: use_build_context_synchronously
                              const SnackBar(
                                content: Text('邀请已发送（邀请链接仅在创建时可见）'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }

                          // 刷新邀请列表
                          _loadInvitations();
                        } catch (e) {
                          await Future.microtask(() {});
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar( // ignore: use_build_context_synchronously
                            SnackBar(
                              content: Text('发送失败：$e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      },
                      label: const Text('发送邀请'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
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
              backgroundColor: Colors.green,
            ),
          );

          _loadInvitations();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('撤销失败：$e'),
              backgroundColor: Colors.red,
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
            const SizedBox(height: 12),
            const Text('邀请链接仅此一次可见，请及时分享给受邀人：'),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                link,
                style: const TextStyle(fontSize: 13),
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
        return (Colors.grey, '已过期');
      case 'revoked':
        return (Colors.grey, '已撤销');
      case 'pending':
      default:
        return (Colors.orange, '待接受');
    }
  }

  @override
  Widget build(BuildContext context) {
    final (statusColor, statusText) = _statusDisplay(invitation.status);
    final roleText = invitation.roleCodes.isEmpty
        ? '未指定'
        : invitation.roleCodes
            .map((c) => OrgMemberRoleExtension.fromApiValue(c).displayName)
            .join('、');

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
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
            const Divider(height: 24),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invitation.email,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '角色：$roleText',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                if (invitation.organization != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '组织：${invitation.organization}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
                if (invitation.inviterName != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '邀请人：${invitation.inviterName}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ],
            ),
            if (invitation.expiresAt != null) ...[
              const Divider(height: 24),
              Row(
                children: [
                  const Icon(Icons.access_time, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    '有效期至：${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.parse(invitation.expiresAt!))}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
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
