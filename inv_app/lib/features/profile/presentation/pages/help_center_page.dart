import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:inv_app/core/services/contact_service.dart';
import 'package:inv_app/core/services/help_center_config_service.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/widgets/app_toast.dart';
import 'package:inv_app/core/widgets/settings_widgets.dart';
import 'package:inv_app/l10n/app_localizations.dart';

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
      return const Center(child: CircularProgressIndicator());
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
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) => _WorkOrderTile(order: _items[index]),
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

class _WorkOrderTile extends StatelessWidget {
  final WorkOrderItem order;

  const _WorkOrderTile({required this.order});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final (color, label) = _statusOf(l10n, order.status);
    return ListTile(
      leading: Icon(
        Icons.receipt_long_rounded,
        size: 22.sp,
        color: AppColors.purple,
      ),
      title: Text(
        order.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 14.sp, color: AppColors.textPrimary),
      ),
      subtitle: Text(
        '${order.deviceSn.isEmpty ? '' : '${order.deviceSn} · '}'
        '${_formatTime(order.createdAt)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12.sp, color: AppColors.textHint),
      ),
      trailing: Container(
        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8.r),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.sp,
            fontWeight: FontWeight.w600,
            color: color,
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

/// 本地时间格式化：yyyy-MM-dd HH:mm
String _formatTime(DateTime time) {
  final t = time.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}';
}
