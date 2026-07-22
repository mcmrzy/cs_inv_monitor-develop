import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:inv_app/core/components/permission_gate.dart';
import 'package:inv_app/core/entities/organization.dart';
import 'package:inv_app/core/stores/organization_context_store.dart';
import 'package:inv_app/core/widgets/org_selector_dialog.dart';
import 'package:intl/intl.dart';

/// 组织浏览器屏幕
/// 以树形视图展示所有组织，支持切换上下文
class OrganizationBrowserScreen extends StatelessWidget {
  const OrganizationBrowserScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _OrganizationBrowserScreenState();
  }
}

class _OrganizationBrowserScreenState extends StatefulWidget {
  const _OrganizationBrowserScreenState();

  @override
  State<_OrganizationBrowserScreenState> createState() =>
      _OrganizationBrowserScreenStateState();
}

class _OrganizationBrowserScreenStateState
    extends State<_OrganizationBrowserScreenState> {
  late OrganizationContextStore _orgStore;

  @override
  void initState() {
    super.initState();
    _orgStore = context.read<OrganizationContextStore>();

    // 初始化时加载组织列表
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _orgStore.loadAvailableOrganizations();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.business),
            SizedBox(width: 8),
            Text('组织切换'),
          ],
        ),
        actions: [
          // 刷新按钮
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _orgStore.loadAvailableOrganizations(),
            tooltip: '刷新',
          ),

          // 新建组织（仅管理员）
          PermissionGate(
            resource: 'organization',
            action: 'manage',
            child: IconButton(
              icon: const Icon(Icons.add_circle),
              onPressed: _showCreateOrgDialog,
              tooltip: '创建组织',
            ),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _orgStore,
        builder: (context, _) {
          final orgs = _orgStore.availableOrgs;

          // 错误提示
          if (_orgStore.error != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('错误：${_orgStore.error}'),
                  backgroundColor: Colors.red,
                ),
              );
            });
          }

          if (_orgStore.isLoading && orgs.isEmpty) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (orgs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.business_outlined,
                    size: 80,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '暂无组织',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '联系管理员为您添加组织或创建新组织',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[500],
                    ),
                  ),
                  const SizedBox(height: 24),
                  PermissionGate(
                    resource: 'organization',
                    action: 'manage',
                    child: FilledButton.icon(
                      onPressed: _showCreateOrgDialog,
                      icon: const Icon(Icons.add),
                      label: const Text('创建组织'),
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => _orgStore.loadAvailableOrganizations(),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: orgs.length,
              itemBuilder: (context, index) {
                final org = orgs[index];
                return _OrganizationCard(
                  organization: org,
                  isActive: _orgStore.activeOrgId == org.id,
                  onTap: () => _selectOrganization(org),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PermissionGate(
              resource: 'organization',
              action: 'manage',
              child: FloatingActionButton.extended(
                onPressed: _showCreateOrgDialog,
                icon: const Icon(Icons.add),
                label: const Text('新建组织'),
              ),
            ),
            const SizedBox(height: 16),
            FloatingActionButton(
              heroTag: 'orgSwitch',
              onPressed: () async {
                final result = await showOrgSelectorDialog(context);
                if (result == true) {
                  // 用户切换了组织，可以刷新当前页面
                }
              },
              tooltip: '切换组织',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.swap_horiz),
                  const SizedBox(width: 8),
                  if (_orgStore.activeOrgName != null)
                    Text(
                      _orgStore.activeOrgName!.substring(
                        0,
                        _orgStore.activeOrgName!.length > 6
                            ? 6
                            : _orgStore.activeOrgName!.length,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectOrganization(Organization org) async {
    final wasChanged = await showOrgSelectorDialog(context);

    if (wasChanged != true && mounted) {
      // 如果未切换，直接使用 ListTile 点击效果
      _orgStore.setActiveOrganization(org.id, org.name);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已切换到 "${org.name}"'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _showCreateOrgDialog() async {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('创建新组织'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: '组织名称',
                    hintText: '请输入组织名称',
                    prefixIcon: Icon(Icons.business),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: '描述（可选）',
                    hintText: '请输入组织描述',
                    prefixIcon: Icon(Icons.description),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('请输入组织名称')),
                  );
                  return;
                }

                try {
                  final newOrg = await _orgStore.apiService.createOrganization(
                    name: name,
                    description: descriptionController.text.trim().isEmpty
                        ? null
                        : descriptionController.text.trim(),
                  );

                  _orgStore.addOrganization(newOrg);

                  await Future.microtask(() {});
                  if (!mounted) return;
                  Navigator.pop(context); // ignore: use_build_context_synchronously
                  ScaffoldMessenger.of(context).showSnackBar( // ignore: use_build_context_synchronously
                    SnackBar(
                      content: Text('已创建组织 "${newOrg.name}"'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } catch (e) {
                  await Future.microtask(() {});
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar( // ignore: use_build_context_synchronously
                    SnackBar(
                      content: Text('创建失败：$e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              child: const Text('创建'),
            ),
          ],
        );
      },
    );
  }
}

/// 组织卡片组件
class _OrganizationCard extends StatelessWidget {
  final Organization organization;
  final bool isActive;
  final VoidCallback? onTap;

  const _OrganizationCard({
    required this.organization,
    this.isActive = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: isActive ? 4 : 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isActive ? Colors.blue : Colors.transparent,
          width: isActive ? 2 : 0,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // 图标区域
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: isActive
                      ? const LinearGradient(
                          colors: [Colors.blue, Colors.lightBlueAccent],
                        )
                      : const LinearGradient(
                          colors: [Colors.grey, Colors.grey],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.business,
                  color: Colors.white,
                  size: 32,
                ),
              ),

              const SizedBox(width: 16),

              // 组织信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          organization.name,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isActive ? Colors.blue : Colors.black87,
                          ),
                        ),
                        if (isActive) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              '当前',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),

                    if (organization.description != null &&
                        organization.description!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        organization.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],

                    const SizedBox(height: 8),

                    // 统计信息
                    Wrap(
                      spacing: 16,
                      runSpacing: 4,
                      children: [
                        _StatChip(
                          icon: Icons.people,
                          label: '${organization.memberCount} 成员',
                        ),
                        _StatChip(
                          icon: Icons.devices,
                          label: '${organization.deviceCount} 设备',
                        ),
                        if (organization.createdAt != null)
                          _StatChip(
                            icon: Icons.calendar_today,
                            label:
                                '创建于 ${DateFormat('yyyy-MM-dd').format(DateTime.parse(organization.createdAt!))}',
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // 操作按钮
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (value) {
                  // TODO: 实现具体操作
                },
                itemBuilder: (context) {
                  final canManage =
                      PermChecker.has(context, 'organization', 'manage');
                  final canManageDevice =
                      PermChecker.has(context, 'device', 'manage');
                  return [
                    const PopupMenuItem(
                      value: 'view',
                      child: Row(
                        children: [
                          Icon(Icons.visibility),
                          SizedBox(width: 8),
                          Text('查看详情'),
                        ],
                      ),
                    ),
                    if (canManage)
                      const PopupMenuItem(
                        value: 'members',
                        child: Row(
                          children: [
                            Icon(Icons.people),
                            SizedBox(width: 8),
                            Text('管理成员'),
                          ],
                        ),
                      ),
                    if (canManageDevice)
                      const PopupMenuItem(
                        value: 'devices',
                        child: Row(
                          children: [
                            Icon(Icons.devices),
                            SizedBox(width: 8),
                            Text('管理设备'),
                          ],
                        ),
                      ),
                    const PopupMenuItem(
                      value: 'settings',
                      child: Row(
                        children: [
                          Icon(Icons.settings),
                          SizedBox(width: 8),
                          Text('设置'),
                        ],
                      ),
                    ),
                  ];
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 统计 Chip 组件
class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _StatChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey[700]),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }
}
