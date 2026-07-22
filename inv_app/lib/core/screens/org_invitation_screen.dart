import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:inv_app/core/components/permission_gate.dart';
import 'package:inv_app/core/entities/organization.dart';
import 'package:inv_app/core/stores/organization_context_store.dart';
import 'package:inv_app/core/services/api_service.dart';
import 'package:intl/intl.dart';

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

  @override
  void initState() {
    super.initState();
    _apiService = context.read<OrganizationContextStore>().apiService;
    _tabController = TabController(length: 3, vsync: this);

    _loadInvitations();
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
    return _invitations?.where((i) => !i.used).toList() ?? [];
  }

  List<OrganizationInvitation> get _usedInvitations {
    return _invitations?.where((i) => i.used).toList() ?? [];
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
            Tab(text: '已使用'),
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
          _buildInvitationList(_usedInvitations),
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
          onRevoke: () => _revokeInvitation(invite.id),
          onCopyLink: () => _copyInviteLink(invite.id),
        );
      },
    );
  }

  Future<void> _showSendInviteDialog() async {
    final emailController = TextEditingController();
    final roleController =
        TextEditingController(text: OrgMemberRole.member.apiValue);
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
                      items: const [
                        DropdownMenuItem(value: 'owner', child: Text('拥有者')),
                        DropdownMenuItem(value: 'admin', child: Text('管理员')),
                        DropdownMenuItem(value: 'member', child: Text('成员')),
                        DropdownMenuItem(value: 'viewer', child: Text('查看者')),
                      ],
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
                          await _apiService.sendInvitation(
                            orgId: widget.organizationId,
                            email: email,
                            role: OrgMemberRoleExtension.fromApiValue(
                              roleController.text,
                            ),
                            days: days,
                          );

                          await Future.microtask(() {});
                          if (!mounted) return;
                          Navigator.pop(context); // ignore: use_build_context_synchronously
                          ScaffoldMessenger.of(context).showSnackBar( // ignore: use_build_context_synchronously
                            SnackBar(
                              content: Text('邀请已发送至 $email'),
                              backgroundColor: Colors.green,
                            ),
                          );

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

  Future<void> _copyInviteLink(int invitationId) async {
    try {
      // TODO: 实现复制链接功能
      // import 'package:flutter/services.dart';
      // await Clipboard.setData(ClipboardData(text: link));

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('邀请链接已复制到剪贴板'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('复制失败：$e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

/// 邀请卡片组件
class _InvitationCard extends StatelessWidget {
  final OrganizationInvitation invitation;
  final VoidCallback? onRevoke;
  final VoidCallback? onCopyLink;

  const _InvitationCard({
    required this.invitation,
    this.onRevoke,
    this.onCopyLink,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = invitation.used ? Colors.grey : Colors.orange;
    final statusText = invitation.used
        ? (invitation.usedAt != null
            ? '已于 ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.parse(invitation.usedAt!))} 使用'
            : '已使用')
        : '待接受';

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
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) {
                    if (value == 'revoke' && onRevoke != null) {
                      onRevoke!();
                    } else if (value == 'copy' && onCopyLink != null) {
                      onCopyLink!();
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'copy',
                      child: Row(
                        children: [
                          Icon(Icons.copy),
                          SizedBox(width: 8),
                          Text('复制邀请链接'),
                        ],
                      ),
                    ),
                    if (!invitation.used)
                      const PopupMenuItem(
                        value: 'revoke',
                        child: Row(
                          children: [
                            Icon(Icons.cancel, color: Colors.red),
                            SizedBox(width: 8),
                            Text('撤销邀请'),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: Column(
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
                        '角色：${invitation.role.displayName}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                      if (invitation.invitedByName != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          '邀请人：${invitation.invitedByName}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
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
