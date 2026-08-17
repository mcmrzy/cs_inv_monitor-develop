import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:inv_app/core/config/app_config.dart';
import 'package:inv_app/core/services/contact_service.dart';
import 'package:inv_app/core/services/help_center_config_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/widgets/app_toast.dart';
import 'package:inv_app/core/widgets/settings_widgets.dart';
import 'package:inv_app/l10n/app_localizations.dart';
import 'package:inv_app/core/widgets/skeleton_widgets.dart';

/// 帮助中心页（需求 14）
///
/// 区块：
/// - 自助服务：设备/App/系统说明书（文档 URL 由后端 /config/help-center
///   动态下发，经 [HelpCenterConfigService] 拉取，失败回退内置默认值；
///   无 URL 时提示"文档暂未开放"。无 WebView 依赖，用系统浏览器打开）。
/// - 客服支持：电话客服（号码由后端配置下发）+ 在线客服（复用
///   [ContactService]）。
/// - 常见问题：FAQ 列表（后端配置下发，未配置时不展示）。
/// - 我的工单：列表 + 提交表单（对接后端 work-order API）。
class HelpCenterPage extends StatefulWidget {
  const HelpCenterPage({super.key});

  @override
  State<HelpCenterPage> createState() => _HelpCenterPageState();
}

class _HelpCenterPageState extends State<HelpCenterPage> {
  /// 后端下发的配置；加载完成前使用内置默认值，避免闪烁
  HelpCenterConfig _config = HelpCenterConfig.fallback;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final cfg = await HelpCenterConfigService().fetch();
    if (!mounted) return;
    setState(() => _config = cfg);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.helpCenter)),
      body: ListView(
        padding: EdgeInsets.only(bottom: 24.h),
        children: [
          SettingsSectionTitle(
            icon: Icons.menu_book_rounded,
            title: l10n.helpSelfService,
            accent: AppColors.teal,
          ),
          SettingsCard([
            SettingsValueRow(
              icon: Icons.developer_board_rounded,
              accent: AppColors.teal,
              title: l10n.helpDocDevice,
              subtitle: l10n.helpSelfServiceHint,
              onTap: () => _openDoc(context, _config.deviceManualUrl),
            ),
            SettingsValueRow(
              icon: Icons.phone_android_rounded,
              accent: AppColors.teal,
              title: l10n.helpDocApp,
              subtitle: l10n.helpSelfServiceHint,
              onTap: () => _openDoc(context, _config.appManualUrl),
            ),
            SettingsValueRow(
              icon: Icons.cloud_rounded,
              accent: AppColors.teal,
              title: l10n.helpDocSystem,
              subtitle: l10n.helpSelfServiceHint,
              onTap: () => _openDoc(context, _config.systemManualUrl),
            ),
          ]),
          SettingsSectionTitle(
            icon: Icons.support_agent_rounded,
            title: l10n.helpCustomerService,
            accent: AppColors.blue,
          ),
          SettingsCard([
            SettingsValueRow(
              icon: Icons.phone_rounded,
              accent: AppColors.blue,
              title: l10n.helpPhoneSupport,
              subtitle:
                  '${_config.servicePhone} · ${l10n.helpPhoneSupportHint}',
              onTap: () => ContactService().makePhoneCall(_config.servicePhone),
            ),
            SettingsValueRow(
              icon: Icons.chat_rounded,
              accent: AppColors.blue,
              title: l10n.helpOnlineSupport,
              subtitle: l10n.helpOnlineSupportHint,
              onTap: () => ContactService().openChat(),
            ),
          ]),
          // 常见问题（后端配置下发，未配置时不展示）
          if (_config.faqs.isNotEmpty) ...[
            SettingsSectionTitle(
              icon: Icons.help_outline_rounded,
              title: l10n.helpFaq,
              accent: AppColors.purple,
            ),
            SettingsCard([
              for (final faq in _config.faqs)
                ExpansionTile(
                  shape: const Border(),
                  title: Text(
                    faq.question,
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  childrenPadding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 14.h),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        faq.answer,
                        style: TextStyle(
                          fontSize: 13.sp,
                          height: 1.5,
                          color: AppColors.textHint,
                        ),
                      ),
                    ),
                  ],
                ),
            ]),
          ],
          SettingsSectionTitle(
            icon: Icons.assignment_rounded,
            title: l10n.helpWorkOrder,
            accent: AppColors.purple,
          ),
          SettingsCard([
            SettingsValueRow(
              icon: Icons.receipt_long_rounded,
              accent: AppColors.purple,
              title: l10n.helpWorkOrder,
              subtitle: l10n.helpWorkOrderHint,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const _WorkOrdersPage(),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Future<void> _openDoc(BuildContext context, String url) async {
    final l10n = AppLocalizations.of(context)!;
    if (url.isEmpty) {
      AppToast.show(context, l10n.helpDocUnavailable, type: ToastType.info);
      return;
    }
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      if (context.mounted) {
        AppToast.show(context, l10n.helpDocUnavailable, type: ToastType.info);
      }
    }
  }
}

/// 工单列表 + 提交表单（对接后端 /work-orders）
class _WorkOrdersPage extends StatefulWidget {
  const _WorkOrdersPage();

  @override
  State<_WorkOrdersPage> createState() => _WorkOrdersPageState();
}

class _WorkOrdersPageState extends State<_WorkOrdersPage> {
  List<WorkOrderItem> _items = const [];
  bool _loading = true;

  /// 状态筛选 Tab 对应的后端 status 值（空=全部；resolved,closed 为已完成）
  static const List<String> _statusTabs = [
    '',
    'open',
    'in_progress',
    'resolved,closed',
  ];
  String _statusFilter = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final dio = getIt<Dio>();
      final response = await dio.get(
        '/work-orders',
        queryParameters: {
          'page': 1,
          'page_size': 50,
          if (_statusFilter.isNotEmpty) 'status': _statusFilter,
        },
      );
      final data = response.data;
      if (data is Map<String, dynamic> && data['code'] == 0) {
        final payload = (data['data'] as Map<String, dynamic>?) ?? {};
        final items = (payload['items'] as List? ?? const [])
            .map(
              (e) =>
                  WorkOrderItem.fromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList();
        if (!mounted) return;
        setState(() {
          _items = items;
          _loading = false;
        });
      } else {
        throw Exception(data is Map ? data['message'] : 'bad response');
      }
    } catch (e) {
      debugPrint('[_WorkOrdersPage] load failed: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _showSubmitDialog() async {
    final l10n = AppLocalizations.of(context)!;
    final titleController = TextEditingController();
    final descController = TextEditingController();
    final selectedImages = <XFile>[];
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.workOrderSubmit),
        content: StatefulBuilder(
          builder: (innerContext, setDialogState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                maxLength: 50,
                decoration: InputDecoration(
                  labelText: l10n.workOrderTitleLabel,
                  hintText: l10n.workOrderTitleHint,
                ),
              ),
              SizedBox(height: 8.h),
              TextField(
                controller: descController,
                maxLines: 4,
                maxLength: 500,
                decoration: InputDecoration(
                  labelText: l10n.workOrderDescLabel,
                  hintText: l10n.workOrderDescHint,
                  alignLabelWithHint: true,
                ),
              ),
              SizedBox(height: 12.h),
              _buildAttachmentPicker(
                innerContext,
                l10n,
                selectedImages,
                setDialogState,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              if (titleController.text.trim().isEmpty ||
                  descController.text.trim().isEmpty) {
                AppToast.show(
                  dialogContext,
                  l10n.str('work_order_required'),
                  type: ToastType.info,
                );
                return;
              }
              Navigator.pop(dialogContext, true);
            },
            child: Text(l10n.workOrderSubmit),
          ),
        ],
      ),
    );
    if (submitted != true || !mounted) return;

    try {
      final dio = getIt<Dio>();
      final response = await dio.post(
        '/work-orders',
        data: {
          'title': titleController.text.trim(),
          'description': descController.text.trim(),
          'priority': 'medium',
        },
      );
      final data = response.data;
      if (data is Map<String, dynamic> && data['code'] == 0) {
        // 创建成功后上传附件（可选，失败不阻断工单提交）
        final orderId =
            ((data['data'] as Map?) ?? const {})['id']?.toString() ?? '';
        if (orderId.isNotEmpty && selectedImages.isNotEmpty) {
          try {
            await _uploadAttachments(orderId, selectedImages);
          } catch (e) {
            debugPrint('[_WorkOrdersPage] upload attachments failed: $e');
            if (!mounted) return;
            AppToast.show(
              context,
              l10n.workOrderAttachFailed,
              type: ToastType.error,
            );
          }
        }
        if (!mounted) return;
        AppToast.show(
          context,
          l10n.workOrderSubmitted,
          type: ToastType.success,
        );
        await _load();
      } else {
        throw Exception(data is Map ? data['message'] : 'bad response');
      }
    } catch (e) {
      debugPrint('[_WorkOrdersPage] submit failed: $e');
      if (!mounted) return;
      AppToast.show(
        context,
        l10n.str('work_order_submit_failed'),
        type: ToastType.error,
      );
    }
  }

  /// 附件选择区：已选图片缩略图（可移除）+ 添加按钮（最多 5 张）
  Widget _buildAttachmentPicker(
    BuildContext dialogContext,
    AppLocalizations l10n,
    List<XFile> selected,
    void Function(VoidCallback) setDialogState,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: selected.isEmpty
              ? Text(
                  l10n.workOrderAttachHint,
                  style: TextStyle(fontSize: 12.sp, color: AppColors.textHint),
                )
              : Wrap(
                  spacing: 8.w,
                  runSpacing: 8.h,
                  children: [
                    for (var i = 0; i < selected.length; i++)
                      _attachmentThumb(
                        dialogContext,
                        l10n,
                        selected,
                        i,
                        setDialogState,
                      ),
                  ],
                ),
        ),
        TextButton.icon(
          onPressed: selected.length >= 5
              ? null
              : () => _pickAttachmentImages(
                    dialogContext,
                    l10n,
                    selected,
                    setDialogState,
                  ),
          icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
          label: Text(l10n.workOrderAddImage),
        ),
      ],
    );
  }

  /// 单张已选图片缩略图（右上角可移除）
  Widget _attachmentThumb(
    BuildContext dialogContext,
    AppLocalizations l10n,
    List<XFile> selected,
    int index,
    void Function(VoidCallback) setDialogState,
  ) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8.r),
          child: Image.file(
            File(selected[index].path),
            width: 52.w,
            height: 52.w,
            fit: BoxFit.cover,
          ),
        ),
        Positioned(
          top: -6.h,
          right: -6.w,
          child: GestureDetector(
            onTap: () => setDialogState(() => selected.removeAt(index)),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.close, size: 12.sp, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  /// 从相册选图（最多 5 张，超限提示）
  Future<void> _pickAttachmentImages(
    BuildContext dialogContext,
    AppLocalizations l10n,
    List<XFile> selected,
    void Function(VoidCallback) setDialogState,
  ) async {
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage(
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );
    if (picked.isEmpty) return;
    final remaining = 5 - selected.length;
    if (picked.length > remaining) {
      AppToast.show(
        dialogContext,
        l10n.workOrderAttachHint,
        type: ToastType.info,
      );
    }
    setDialogState(() => selected.addAll(picked.take(remaining)));
  }

  /// 上传附件（multipart files 字段，1-5 张，仅图片）
  Future<void> _uploadAttachments(String orderId, List<XFile> images) async {
    final dio = getIt<Dio>();
    final formData = FormData();
    for (final image in images) {
      formData.files.add(MapEntry(
        'files',
        await MultipartFile.fromFile(image.path, filename: image.name),
      ));
    }
    final response = await dio.post(
      '/work-orders/$orderId/attachments',
      data: formData,
    );
    final data = response.data;
    if (!(data is Map<String, dynamic> && data['code'] == 0)) {
      throw Exception('upload attachments failed');
    }
  }

  /// 单击卡片：进入工单详情页
  void _openDetail(WorkOrderItem order) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _WorkOrderDetailPage(order: order),
      ),
    );
  }

  /// 长按卡片：弹出操作菜单（查看详情 / 复制编号 / 复制SN / 删除）
  void _showActions(WorkOrderItem order) {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 24.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 拖动指示条
              Container(
                width: 36.w,
                height: 4.h,
                decoration: BoxDecoration(
                  color: AppColors.textHint.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2.r),
                ),
              ),
              SizedBox(height: 16.h),
              // 当前工单摘要
              Row(
                children: [
                  _PriorityBadge(priority: order.priority),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Text(
                      order.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12.h),
              Divider(color: AppColors.divider),
              SizedBox(height: 4.h),
              _WorkOrderActionItem(
                icon: Icons.visibility_outlined,
                label: l10n.workOrderViewDetail,
                onTap: () {
                  Navigator.pop(sheetContext);
                  _openDetail(order);
                },
              ),
              _WorkOrderActionItem(
                icon: Icons.copy_rounded,
                label: l10n.workOrderCopyId,
                onTap: () {
                  Navigator.pop(sheetContext);
                  _copy(order.id);
                },
              ),
              if (order.deviceSn.isNotEmpty)
                _WorkOrderActionItem(
                  icon: Icons.copy_all_rounded,
                  label: l10n.str('work_order_copy_sn'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _copy(order.deviceSn);
                  },
                ),
              _WorkOrderActionItem(
                icon: Icons.delete_outline_rounded,
                label: l10n.str('work_order_delete'),
                destructive: true,
                onTap: () {
                  Navigator.pop(sheetContext);
                  _deleteOrder(order);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _copy(String text) async {
    final l10n = AppLocalizations.of(context)!;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      AppToast.show(context, l10n.str('op_log_copied'), type: ToastType.success);
    }
  }

  /// 删除工单（二次确认）
  Future<void> _deleteOrder(WorkOrderItem order) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: AppColors.error, size: 22.sp),
            SizedBox(width: 8.w),
            Text(l10n.str('work_order_delete'),
                style: TextStyle(fontSize: 16.sp)),
          ],
        ),
        content: Text(
          l10n.str('work_order_delete_confirm'),
          style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.str('work_order_delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final dio = getIt<Dio>();
      final response = await dio.delete('/work-orders/${order.id}');
      final data = response.data;
      if (data is Map<String, dynamic> && data['code'] == 0) {
        if (!mounted) return;
        AppToast.show(context, l10n.str('work_order_deleted'),
            type: ToastType.success);
        await _load();
      } else {
        throw Exception(data is Map ? data['message'] : 'bad response');
      }
    } catch (e) {
      debugPrint('[_WorkOrdersPage] delete failed: $e');
      if (!mounted) return;
      AppToast.show(context, l10n.str('work_order_load_failed'),
          type: ToastType.error);
    }
  }

  void _onTabChanged(int index) {
    if (index < 0 || index >= _statusTabs.length) return;
    if (_statusFilter == _statusTabs[index]) return;
    _statusFilter = _statusTabs[index];
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return DefaultTabController(
      length: _statusTabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.helpWorkOrder),
          bottom: TabBar(
            onTap: _onTabChanged,
            labelStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600),
            unselectedLabelStyle: TextStyle(fontSize: 13.sp),
            tabs: [
              Tab(text: l10n.workOrderTabAll),
              Tab(text: l10n.workOrderStatusPending),
              Tab(text: l10n.workOrderStatusProcessing),
              Tab(text: l10n.workOrderTabDone),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _showSubmitDialog,
          icon: const Icon(Icons.add),
          label: Text(l10n.workOrderSubmit),
        ),
        body: _buildBody(l10n),
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_loading) {
      return const PageSkeleton();
    }
    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 48.sp,
              color: AppColors.textHint,
            ),
            SizedBox(height: 12.h),
            Text(
              l10n.workOrderEmpty,
              style: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 88.h),
        itemCount: _items.length,
        itemBuilder: (context, index) => Padding(
          padding: EdgeInsets.only(bottom: 10.h),
          child: _WorkOrderCard(
            order: _items[index],
            onTap: () => _openDetail(_items[index]),
            onLongPress: () => _showActions(_items[index]),
          ),
        ),
      ),
    );
  }
}

class WorkOrderItem {
  final String id;
  final String title;
  final String status;
  final String priority;
  final String deviceSn;
  final DateTime createdAt;

  const WorkOrderItem({
    required this.id,
    required this.title,
    required this.status,
    required this.priority,
    required this.deviceSn,
    required this.createdAt,
  });

  factory WorkOrderItem.fromJson(Map<String, dynamic> json) {
    return WorkOrderItem(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      status: json['status'] as String? ?? 'open',
      priority: json['priority'] as String? ?? '',
      deviceSn: json['deviceSn'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

/// 卡片式工单项：优先级图标圆底 + 标题 + 元信息 + 状态徽章
///
/// 单击 [onTap] 进入详情页；长按 [onLongPress] 弹出操作菜单。
class _WorkOrderCard extends StatelessWidget {
  final WorkOrderItem order;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _WorkOrderCard({
    required this.order,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final (statusColor, statusLabel) = _statusOf(l10n, order.status);
    return Material(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(16.r),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(16.r),
        child: Container(
          padding: EdgeInsets.all(14.w),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              // 优先级图标圆底
              _PriorityBadge(priority: order.priority),
              SizedBox(width: 12.w),
              // 标题 + 元信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.sp,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      '${order.deviceSn.isEmpty ? '' : '${order.deviceSn} · '}'
                      '${_formatTime(order.createdAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: AppColors.textHint,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8.w),
              // 状态徽章
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 10.sp,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  (Color, String) _statusOf(AppLocalizations l10n, String status) {
    return switch (status) {
      'open' => (AppColors.warning, l10n.workOrderStatusPending),
      'in_progress' => (AppColors.primary, l10n.workOrderStatusProcessing),
      'resolved' => (AppColors.successLight, l10n.workOrderStatusResolved),
      'closed' => (AppColors.textHint, l10n.workOrderStatusClosed),
      _ => (AppColors.textHint, status),
    };
  }
}

/// 优先级图标圆底徽章
class _PriorityBadge extends StatelessWidget {
  final String priority;

  const _PriorityBadge({required this.priority});

  /// 优先级主题色：高=红 / 中=橙 / 低=绿
  static Color colorOf(String priority) {
    return switch (priority) {
      'high' => AppColors.errorLight,
      'medium' => AppColors.warning,
      'low' => AppColors.successLight,
      _ => AppColors.textHint,
    };
  }

  static IconData iconOf(String priority) {
    return switch (priority) {
      'high' => Icons.arrow_upward_rounded,
      'medium' => Icons.remove_rounded,
      'low' => Icons.arrow_downward_rounded,
      _ => Icons.flag_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    final accent = colorOf(priority);
    return Container(
      width: 40.w,
      height: 40.w,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(
        iconOf(priority),
        size: 20.sp,
        color: accent,
      ),
    );
  }
}

/// 长按操作菜单项
class _WorkOrderActionItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  const _WorkOrderActionItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        destructive ? AppColors.error : AppColors.textPrimary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12.r),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 8.w),
        child: Row(
          children: [
            Icon(icon, size: 20.sp, color: color),
            SizedBox(width: 12.w),
            Text(
              label,
              style: TextStyle(fontSize: 14.sp, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// 本地时间格式化：yyyy-MM-dd HH:mm
String _formatTime(DateTime time) {
  final t = time.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}';
}

/// 工单详情页（GET /work-orders/:id）
///
/// 展示：头部状态/优先级、完整字段、问题描述、处理结果、
/// 处理进度时间线、附件图片（点击放大）。
class _WorkOrderDetailPage extends StatefulWidget {
  final WorkOrderItem order;

  const _WorkOrderDetailPage({required this.order});

  @override
  State<_WorkOrderDetailPage> createState() => _WorkOrderDetailPageState();
}

class _WorkOrderDetailPageState extends State<_WorkOrderDetailPage> {
  WorkOrderDetail? _detail;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final dio = getIt<Dio>();
      final response = await dio.get('/work-orders/${widget.order.id}');
      final data = response.data;
      if (data is Map<String, dynamic> && data['code'] == 0) {
        final payload = Map<String, dynamic>.from(
          (data['data'] as Map?) ?? const {},
        );
        if (!mounted) return;
        setState(() {
          _detail = WorkOrderDetail.fromJson(payload);
          _loading = false;
        });
      } else {
        throw Exception(data is Map ? data['message'] : 'bad response');
      }
    } catch (e) {
      debugPrint('[_WorkOrderDetailPage] load failed: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.workOrderDetail)),
      body: _buildBody(context, l10n),
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations l10n) {
    if (_loading) {
      return const PageSkeleton();
    }
    if (_failed || _detail == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.workOrderLoadFailed,
              style: TextStyle(fontSize: 14.sp, color: AppColors.textHint),
            ),
            SizedBox(height: 12.h),
            OutlinedButton(onPressed: _load, child: Text(l10n.retry)),
          ],
        ),
      );
    }
    final detail = _detail!;
    final (statusColor, statusLabel) = _detailStatusOf(l10n, detail.status);
    return ListView(
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 32.h),
      children: [
        // 头部卡片：状态 + 优先级 + 标题 + 工单号
        _DetailSection(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _StatusChip(color: statusColor, label: statusLabel),
                  SizedBox(width: 8.w),
                  _PriorityChip(priority: detail.priority, l10n: l10n),
                ],
              ),
              SizedBox(height: 12.h),
              Text(
                detail.title,
                style: TextStyle(
                  fontSize: 17.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(height: 6.h),
              Row(
                children: [
                  Text(
                    '${l10n.workOrderNo}：#${detail.id}',
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: AppColors.textHint,
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: () async {
                      await Clipboard.setData(
                          ClipboardData(text: detail.id));
                      if (context.mounted) {
                        AppToast.show(context, l10n.str('op_log_copied'),
                            type: ToastType.success);
                      }
                    },
                    borderRadius: BorderRadius.circular(8.r),
                    child: Padding(
                      padding: EdgeInsets.all(4.w),
                      child: Icon(
                        Icons.copy_rounded,
                        size: 16.sp,
                        color: AppColors.textHint,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(height: 12.h),
        // 基本信息
        _DetailSection(
          title: Icons.info_outline_rounded,
          child: Column(
            children: [
              _InfoRow(label: l10n.workOrderPriority, value: _priorityLabel(l10n, detail.priority)),
              if (detail.deviceSn.isNotEmpty) ...[
                SizedBox(height: 10.h),
                _InfoRow(
                  label: l10n.opLogDevice,
                  value: detail.deviceSn,
                  onCopy: () => _copyText(detail.deviceSn, context),
                ),
              ],
              if (detail.templateType.isNotEmpty) ...[
                SizedBox(height: 10.h),
                _InfoRow(
                  label: l10n.str('work_order_template'),
                  value: _templateLabel(detail.templateType),
                ),
              ],
              SizedBox(height: 10.h),
              _InfoRow(label: l10n.workOrderCreator, value: detail.creatorName.isEmpty ? '-' : detail.creatorName),
              SizedBox(height: 10.h),
              _InfoRow(
                label: l10n.workOrderAssignee,
                value: detail.assigneeName.isEmpty
                    ? l10n.str('work_order_no_assignee')
                    : detail.assigneeName,
              ),
              SizedBox(height: 10.h),
              _InfoRow(label: l10n.workOrderCreatedAt, value: _formatTime(detail.createdAt)),
              SizedBox(height: 10.h),
              _InfoRow(label: l10n.workOrderUpdatedAt, value: _formatTime(detail.updatedAt)),
              if (detail.slaDeadline != null) ...[
                SizedBox(height: 10.h),
                _InfoRow(
                  label: l10n.str('work_order_sla_deadline'),
                  value: _formatTime(detail.slaDeadline!),
                ),
              ],
            ],
          ),
        ),
        SizedBox(height: 12.h),
        // 问题描述
        _DetailSection(
          title: Icons.notes_rounded,
          child: Text(
            detail.description.isEmpty ? '-' : detail.description,
            style: TextStyle(
              fontSize: 14.sp,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        // 处理结果
        if (detail.resolution.isNotEmpty) ...[
          SizedBox(height: 12.h),
          _DetailSection(
            title: Icons.task_alt_rounded,
            child: Text(
              detail.resolution,
              style: TextStyle(
                fontSize: 14.sp,
                height: 1.6,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
        // 处理进度时间线
        if (detail.timeline.isNotEmpty) ...[
          SizedBox(height: 12.h),
          _DetailSection(
            title: Icons.timeline_rounded,
            child: Column(
              children: [
                for (var i = 0; i < detail.timeline.length; i++)
                  _TimelineItem(
                    event: detail.timeline[i],
                    isLast: i == detail.timeline.length - 1,
                  ),
              ],
            ),
          ),
        ],
        // 附件
        if (detail.attachments.isNotEmpty) ...[
          SizedBox(height: 12.h),
          _DetailSection(
            title: Icons.image_rounded,
            child: Wrap(
              spacing: 8.w,
              runSpacing: 8.h,
              children: [
                for (final attachment in detail.attachments)
                  _AttachmentThumb(
                    attachment: attachment,
                    onTap: () => _previewImage(context, attachment),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _copyText(String text, BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      AppToast.show(context, l10n.str('op_log_copied'), type: ToastType.success);
    }
  }

  /// 附件全屏预览（支持双指缩放）
  void _previewImage(BuildContext context, WorkOrderAttachment attachment) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                maxScale: 5,
                child: Center(
                  child: Image.network(
                    attachment.fullUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(Icons.broken_image_outlined,
                          color: Colors.white54, size: 48),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.of(dialogContext).padding.top + 8.h,
              right: 12.w,
              child: IconButton(
                onPressed: () => Navigator.pop(dialogContext),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  (Color, String) _detailStatusOf(AppLocalizations l10n, String status) {
    return switch (status) {
      'open' => (AppColors.warning, l10n.workOrderStatusPending),
      'in_progress' => (AppColors.primary, l10n.workOrderStatusProcessing),
      'resolved' => (AppColors.successLight, l10n.workOrderStatusResolved),
      'closed' => (AppColors.textHint, l10n.workOrderStatusClosed),
      _ => (AppColors.textHint, status),
    };
  }

  String _priorityLabel(AppLocalizations l10n, String priority) {
    return switch (priority) {
      'high' => l10n.str('work_order_priority_high'),
      'medium' => l10n.str('work_order_priority_medium'),
      'low' => l10n.str('work_order_priority_low'),
      _ => priority.isEmpty ? '-' : priority,
    };
  }

  String _templateLabel(String templateType) {
    return switch (templateType) {
      'repair' => '设备故障',
      'maintenance' => '定期维护',
      'inspection' => '设备巡检',
      'installation' => '安装调试',
      _ => templateType.isEmpty ? '-' : templateType,
    };
  }
}

/// 工单详情数据模型（GET /work-orders/:id 全字段）
class WorkOrderDetail {
  final String id;
  final String title;
  final String description;
  final String status;
  final String priority;
  final String deviceSn;
  final String creatorName;
  final String assigneeName;
  final String templateType;
  final String resolution;
  final DateTime? slaDeadline;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<WorkOrderTimelineEvent> timeline;
  final List<WorkOrderAttachment> attachments;

  const WorkOrderDetail({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.priority,
    required this.deviceSn,
    required this.creatorName,
    required this.assigneeName,
    required this.templateType,
    required this.resolution,
    this.slaDeadline,
    required this.createdAt,
    required this.updatedAt,
    required this.timeline,
    required this.attachments,
  });

  factory WorkOrderDetail.fromJson(Map<String, dynamic> json) {
    return WorkOrderDetail(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      status: json['status'] as String? ?? 'open',
      priority: json['priority'] as String? ?? '',
      deviceSn: json['deviceSn'] as String? ?? '',
      creatorName: json['creatorName'] as String? ?? '',
      assigneeName: json['assigneeName'] as String? ?? '',
      templateType: json['templateType'] as String? ?? '',
      resolution: json['resolution'] as String? ?? '',
      slaDeadline: json['slaDeadline'] == null
          ? null
          : DateTime.tryParse(json['slaDeadline'] as String),
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
              DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
              DateTime.now(),
      timeline: (json['timeline'] as List? ?? const [])
          .map((e) => WorkOrderTimelineEvent.fromJson(
              Map<String, dynamic>.from(e as Map)))
          .toList(),
      attachments: (json['attachments'] as List? ?? const [])
          .map((e) => WorkOrderAttachment.fromJson(
              Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
}

/// 时间线事件（状态流转记录）
class WorkOrderTimelineEvent {
  final String status;
  final String operator;
  final String remark;
  final DateTime timestamp;

  const WorkOrderTimelineEvent({
    required this.status,
    required this.operator,
    required this.remark,
    required this.timestamp,
  });

  factory WorkOrderTimelineEvent.fromJson(Map<String, dynamic> json) {
    return WorkOrderTimelineEvent(
      status: json['status'] as String? ?? '',
      operator: json['operator'] as String? ?? '',
      remark: json['remark'] as String? ?? '',
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

/// 工单附件（图片）
class WorkOrderAttachment {
  final String name;
  final String url;

  const WorkOrderAttachment({required this.name, required this.url});

  factory WorkOrderAttachment.fromJson(Map<String, dynamic> json) {
    return WorkOrderAttachment(
      name: json['name'] as String? ?? '',
      url: json['url'] as String? ?? '',
    );
  }

  /// 附件完整 URL：后端返回相对路径 /firmware/...，
  /// 拼接 API 主机地址（去掉 /api/v1 前缀）。
  String get fullUrl {
    final base = AppConfig.apiBaseUrl;
    final host = base.replaceFirst(RegExp(r'/api/v1/*$'), '');
    return url.startsWith('http') ? url : '$host$url';
  }
}

/// 详情区块卡片（可选标题图标）
class _DetailSection extends StatelessWidget {
  final IconData? title;
  final Widget child;

  const _DetailSection({this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: AppColors.border),
      ),
      child: title == null
          ? child
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(title, size: 18.sp, color: AppColors.purple),
                SizedBox(height: 10.h),
                child,
              ],
            ),
    );
  }
}

/// 详情字段行：标签 + 值（可附带复制按钮）
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onCopy;

  const _InfoRow({required this.label, required this.value, this.onCopy});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 76.w,
          child: Text(
            label,
            style: TextStyle(fontSize: 13.sp, color: AppColors.textHint),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13.sp,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        if (onCopy != null)
          InkWell(
            onTap: onCopy,
            borderRadius: BorderRadius.circular(8.r),
            child: Padding(
              padding: EdgeInsets.all(2.w),
              child: Icon(
                Icons.copy_rounded,
                size: 15.sp,
                color: AppColors.textHint,
              ),
            ),
          ),
      ],
    );
  }
}

/// 状态徽章（详情头部用）
class _StatusChip extends StatelessWidget {
  final Color color;
  final String label;

  const _StatusChip({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10.r),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 6.sp, color: color),
          SizedBox(width: 4.w),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.sp,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// 优先级徽章（详情头部用）
class _PriorityChip extends StatelessWidget {
  final String priority;
  final AppLocalizations l10n;

  const _PriorityChip({required this.priority, required this.l10n});

  @override
  Widget build(BuildContext context) {
    final accent = _PriorityBadge.colorOf(priority);
    final label = switch (priority) {
      'high' => l10n.str('work_order_priority_high'),
      'medium' => l10n.str('work_order_priority_medium'),
      'low' => l10n.str('work_order_priority_low'),
      _ => priority.isEmpty ? '-' : priority,
    };
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10.r),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_PriorityBadge.iconOf(priority), size: 12.sp, color: accent),
          SizedBox(width: 4.w),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.sp,
              fontWeight: FontWeight.w600,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}

/// 时间线项：圆点 + 竖线 + 状态/操作人/时间/备注
class _TimelineItem extends StatelessWidget {
  final WorkOrderTimelineEvent event;
  final bool isLast;

  const _TimelineItem({required this.event, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final (color, label) = switch (event.status) {
      'open' => (AppColors.warning, l10n.workOrderStatusPending),
      'in_progress' => (AppColors.primary, l10n.workOrderStatusProcessing),
      'resolved' => (AppColors.successLight, l10n.workOrderStatusResolved),
      'closed' => (AppColors.textHint, l10n.workOrderStatusClosed),
      _ => (AppColors.textHint, event.status),
    };
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 圆点 + 竖线
          SizedBox(
            width: 20.w,
            child: Column(
              children: [
                Container(
                  width: 10.w,
                  height: 10.w,
                  margin: EdgeInsets.only(top: 4.h),
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2.w,
                      color: AppColors.divider,
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(width: 10.w),
          // 内容
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _formatTime(event.timestamp),
                        style: TextStyle(
                          fontSize: 11.sp,
                          color: AppColors.textHint,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    event.operator.isEmpty
                        ? '-'
                        : '操作人：${event.operator}',
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: AppColors.textHint,
                    ),
                  ),
                  if (event.remark.isNotEmpty) ...[SizedBox(height: 2.h),
                    Text(
                      event.remark,
                      style: TextStyle(
                        fontSize: 12.sp,
                        height: 1.4,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 附件缩略图
class _AttachmentThumb extends StatelessWidget {
  final WorkOrderAttachment attachment;
  final VoidCallback onTap;

  const _AttachmentThumb({required this.attachment, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10.r),
        child: Image.network(
          attachment.fullUrl,
          width: 88.w,
          height: 88.w,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            width: 88.w,
            height: 88.w,
            color: AppColors.surfaceHover,
            child: Icon(
              Icons.broken_image_outlined,
              size: 28.sp,
              color: AppColors.textHint,
            ),
          ),
        ),
      ),
    );
  }
}