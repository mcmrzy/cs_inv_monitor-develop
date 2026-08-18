import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';

import 'package:inv_app/core/config/app_config.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/widgets/app_toast.dart';
import 'package:inv_app/core/widgets/skeleton_widgets.dart';
import 'package:inv_app/l10n/app_localizations.dart';

/// 工单列表 + 提交表单（对接后端 /work-orders）
///
/// 状态 Tab（全部/待处理/处理中/已完成）带数量统计；
/// 列表分页加载；提交支持模板/优先级/关联设备选择。
class WorkOrdersPage extends StatefulWidget {
  const WorkOrdersPage({super.key});

  @override
  State<WorkOrdersPage> createState() => _WorkOrdersPageState();
}

class _WorkOrdersPageState extends State<WorkOrdersPage> {
  List<WorkOrderItem> _items = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  static const int _pageSize = 20;
  final ScrollController _scrollController = ScrollController();

  /// 状态筛选 Tab 对应的后端 status 值（空=全部；resolved,closed 为已完成）
  static const List<String> _statusTabs = [
    '',
    'open',
    'in_progress',
    'resolved,closed',
  ];
  String _statusFilter = '';

  /// 当前选中的 Tab 索引（状态驱动，替代 TabController）
  int _tabIndex = 0;

  /// 请求序号守卫：快速切换 Tab 时丢弃乱序响应
  int _reqSeq = 0;

  /// 已有数据时的后台刷新标记（顶部细进度条，不清空列表）
  bool _refreshing = false;

  /// 按 Tab 缓存列表数据（切回已加载的 Tab 直接渲染，不整页重建）
  final Map<int, List<WorkOrderItem>> _tabCache = {};

  /// 按 Tab 缓存 _hasMore 状态
  final Map<int, bool> _tabHasMoreCache = {};

  /// 状态统计（GET /work-orders/statistics）
  int _statTotal = 0;
  int _statOpen = 0;
  int _statInProgress = 0;
  int _statResolved = 0;
  int _statClosed = 0;

  /// 提交表单辅助数据：模板与设备列表
  List<Map<String, dynamic>> _templates = const [];
  List<(String, String)> _deviceOptions = const [];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load(reset: true);
    _loadStats();
    _loadTemplates();
    _loadDeviceOptions();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final nearBottom = _scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 120;
    if (nearBottom &&
        !_loadingMore &&
        _hasMore &&
        !_loading &&
        !_refreshing) {
      _loadMore();
    }
  }

  /// 使所有 Tab 缓存失效（提交/删除工单成功后调用）
  void _invalidateCaches() {
    _tabCache.clear();
    _tabHasMoreCache.clear();
  }

  Future<void> _load({bool reset = false}) async {
    // 请求序号守卫：响应回来时若序号已过期（期间发起了新请求）则丢弃
    final seq = ++_reqSeq;
    final tabIndex = _tabIndex;
    if (reset) {
      setState(() {
        _page = 1;
        _hasMore = true;
        if (_items.isEmpty) {
          // 无数据首次加载：整页骨架屏
          _loading = true;
        } else {
          // 已有数据：后台刷新，顶部细进度条叠在旧列表上
          _refreshing = true;
        }
      });
    }
    try {
      final dio = getIt<Dio>();
      final response = await dio.get(
        '/work-orders',
        queryParameters: {
          'page': _page,
          'page_size': _pageSize,
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
        final total = (payload['total'] as num?)?.toInt() ?? items.length;
        if (!mounted || seq != _reqSeq) return;
        setState(() {
          _items = reset ? items : [..._items, ...items];
          _hasMore = _items.length < total;
          _loading = false;
          _refreshing = false;
          // 同步更新当前 Tab 缓存（首屏与加载更多均更新）
          _tabCache[tabIndex] = _items;
          _tabHasMoreCache[tabIndex] = _hasMore;
        });
      } else {
        throw Exception(data is Map ? data['message'] : 'bad response');
      }
    } catch (e) {
      debugPrint('[WorkOrdersPage] load failed: $e');
      if (!mounted || seq != _reqSeq) return;
      setState(() {
        _loading = false;
        _refreshing = false;
      });
      if (reset) {
        AppToast.show(
          context,
          AppLocalizations.of(context)!.str('work_order_load_failed'),
          type: ToastType.error,
        );
      }
    }
  }

  Future<void> _loadMore() async {
    setState(() {
      _loadingMore = true;
      _page += 1;
    });
    await _load();
    if (!mounted) return;
    setState(() => _loadingMore = false);
  }

  Future<void> _loadStats() async {
    try {
      final dio = getIt<Dio>();
      final response = await dio.get('/work-orders/statistics');
      final data = response.data;
      if (data is Map<String, dynamic> &&
          data['code'] == 0 &&
          data['data'] is Map) {
        final s = data['data'] as Map;
        if (!mounted) return;
        setState(() {
          _statTotal = (s['total'] as num?)?.toInt() ?? 0;
          _statOpen = (s['open'] as num?)?.toInt() ?? 0;
          _statInProgress = (s['inProgress'] as num?)?.toInt() ?? 0;
          _statResolved = (s['resolved'] as num?)?.toInt() ?? 0;
          _statClosed = (s['closed'] as num?)?.toInt() ?? 0;
        });
      }
    } catch (_) {
      // 统计失败不阻塞列表
    }
  }

  /// 工单模板（GET /work-orders/templates，失败回退内置四模板）
  Future<void> _loadTemplates() async {
    try {
      final dio = getIt<Dio>();
      final response = await dio.get('/work-orders/templates');
      final data = response.data;
      if (data is Map<String, dynamic> &&
          data['code'] == 0 &&
          data['data'] is List) {
        final list = (data['data'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        if (list.isNotEmpty && mounted) {
          setState(() => _templates = list);
          return;
        }
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => _templates = WorkOrderTemplate.fallback);
  }

  /// 已绑定设备选项（提交时关联设备 SN，可空）
  Future<void> _loadDeviceOptions() async {
    try {
      final dio = getIt<Dio>();
      final response = await dio.get(
        '/devices',
        queryParameters: {'page': 1, 'page_size': 200},
      );
      final data = response.data;
      if (data is Map<String, dynamic> && data['code'] == 0) {
        final payload = data['data'];
        final list = payload is Map ? (payload['items'] as List? ?? const []) : const [];
        final options = <(String, String)>[];
        for (final e in list) {
          if (e is! Map) continue;
          final sn = (e['sn'] ?? e['device_sn'] ?? '').toString();
          if (sn.isEmpty) continue;
          final name =
              (e['alias'] ?? e['name'] ?? e['device_name'] ?? '').toString();
          options.add((sn, name.isEmpty ? sn : name));
        }
        if (mounted) setState(() => _deviceOptions = options);
      }
    } catch (_) {
      // 设备列表失败：提交时不关联设备即可
    }
  }

  Future<void> _showSubmitDialog() async {
    final l10n = AppLocalizations.of(context)!;
    final titleController = TextEditingController();
    final descController = TextEditingController();
    final selectedImages = <XFile>[];
    // 表单选择项：默认设备故障模板 + 中优先级 + 不关联设备
    var selectedTemplate = _templates.isNotEmpty
        ? (_templates.first['templateId'] ?? 'repair').toString()
        : 'repair';
    var selectedPriority = 'medium';
    var selectedDeviceSn = '';
    final templates = _templates.isNotEmpty
        ? _templates
        : WorkOrderTemplate.fallback;

    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.workOrderSubmit),
        content: SingleChildScrollView(
          child: StatefulBuilder(
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
                // 工单类型（模板）
                _selectRow(
                  icon: Icons.category_rounded,
                  label: l10n.str('work_order_template'),
                  value: _templateTitle(templates, selectedTemplate),
                  onTap: () async {
                    final picked = await _pickTemplate(
                      innerContext,
                      templates,
                      selectedTemplate,
                    );
                    if (picked != null) {
                      setDialogState(() {
                        selectedTemplate = picked;
                        // 模板默认优先级联动
                        final tpl = templates.firstWhere(
                          (t) => (t['templateId'] ?? '') == picked,
                          orElse: () => const {},
                        );
                        final p = (tpl['priority'] ?? '').toString();
                        if (p.isNotEmpty) selectedPriority = p;
                      });
                    }
                  },
                ),
                SizedBox(height: 8.h),
                // 优先级
                _selectRow(
                  icon: Icons.flag_rounded,
                  label: l10n.workOrderPriority,
                  value: _priorityLabel(l10n, selectedPriority),
                  onTap: () async {
                    final picked =
                        await _pickPriority(innerContext, selectedPriority);
                    if (picked != null) {
                      setDialogState(() => selectedPriority = picked);
                    }
                  },
                ),
                SizedBox(height: 8.h),
                // 关联设备（可选）
                _selectRow(
                  icon: Icons.devices_other_rounded,
                  label: l10n.str('work_order_select_device'),
                  value: selectedDeviceSn.isEmpty
                      ? l10n.str('work_order_no_device')
                      : selectedDeviceSn,
                  onTap: () async {
                    final picked = await _pickDevice(
                      innerContext,
                      selectedDeviceSn,
                    );
                    if (picked != null) {
                      setDialogState(() => selectedDeviceSn = picked);
                    }
                  },
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
          'priority': selectedPriority,
          'template_type': selectedTemplate,
          if (selectedDeviceSn.isNotEmpty) 'device_sn': selectedDeviceSn,
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
            debugPrint('[WorkOrdersPage] upload attachments failed: $e');
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
        // 提交成功：所有 Tab 缓存失效，重载当前 Tab 与统计
        _invalidateCaches();
        await _load(reset: true);
        await _loadStats();
      } else {
        throw Exception(data is Map ? data['message'] : 'bad response');
      }
    } catch (e) {
      debugPrint('[WorkOrdersPage] submit failed: $e');
      if (!mounted) return;
      AppToast.show(
        context,
        l10n.str('work_order_submit_failed'),
        type: ToastType.error,
      );
    }
  }

  /// 选择行：标签 + 当前值 + 箭头
  Widget _selectRow({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10.r),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 4.w),
        child: Row(
          children: [
            Icon(icon, size: 18.sp, color: AppColor.textHint(context)),
            SizedBox(width: 8.w),
            Text(
              label,
              style: TextStyle(
                fontSize: 13.sp,
                color: AppColor.textSecondary(context),
              ),
            ),
            const Spacer(),
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w500,
                  color: AppColor.textPrimary(context),
                ),
              ),
            ),
            SizedBox(width: 4.w),
            Icon(
              Icons.arrow_drop_down_rounded,
              size: 18.sp,
              color: AppColor.textHint(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _pickTemplate(
    BuildContext dialogContext,
    List<Map<String, dynamic>> templates,
    String current,
  ) {
    return showDialog<String>(
      context: dialogContext,
      builder: (ctx) => SimpleDialog(
        title: Text(AppLocalizations.of(ctx)!.str('work_order_template')),
        children: [
          for (final tpl in templates)
            SimpleDialogOption(
              onPressed: () =>
                  Navigator.pop(ctx, (tpl['templateId'] ?? '').toString()),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (tpl['title'] ?? '').toString(),
                          style: TextStyle(
                            fontSize: 14.sp,
                            fontWeight: (tpl['templateId'] ?? '') == current
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                        ),
                        if ((tpl['description'] ?? '').toString().isNotEmpty)
                          Text(
                            (tpl['description'] ?? '').toString(),
                            style: TextStyle(
                              fontSize: 12.sp,
                              color: AppColor.textHint(ctx),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if ((tpl['templateId'] ?? '') == current)
                    Icon(Icons.check_rounded,
                        size: 16.sp, color: AppColors.primary),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<String?> _pickPriority(BuildContext dialogContext, String current) {
    final l10n = AppLocalizations.of(dialogContext)!;
    final options = ['high', 'medium', 'low'];
    return showDialog<String>(
      context: dialogContext,
      builder: (ctx) => SimpleDialog(
        title: Text(l10n.workOrderPriority),
        children: [
          for (final p in options)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, p),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _priorityLabel(l10n, p),
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight:
                            p == current ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (p == current)
                    Icon(Icons.check_rounded,
                        size: 16.sp, color: AppColors.primary),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 选择关联设备：第一项为「不关联设备」
  Future<String?> _pickDevice(BuildContext dialogContext, String current) {
    final l10n = AppLocalizations.of(dialogContext)!;
    return showDialog<String>(
      context: dialogContext,
      builder: (ctx) => SimpleDialog(
        title: Text(l10n.str('work_order_select_device')),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ''),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.str('work_order_no_device'),
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: current.isEmpty
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                  ),
                ),
                if (current.isEmpty)
                  Icon(Icons.check_rounded,
                      size: 16.sp, color: AppColors.primary),
              ],
            ),
          ),
          for (final (sn, name) in _deviceOptions)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, sn),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: 14.sp,
                            fontWeight: sn == current
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                        ),
                        Text(
                          sn,
                          style: TextStyle(
                            fontSize: 11.sp,
                            color: AppColor.textHint(ctx),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (sn == current)
                    Icon(Icons.check_rounded,
                        size: 16.sp, color: AppColors.primary),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _templateTitle(List<Map<String, dynamic>> templates, String id) {
    for (final tpl in templates) {
      if ((tpl['templateId'] ?? '') == id) {
        return (tpl['title'] ?? id).toString();
      }
    }
    return id;
  }

  String _priorityLabel(AppLocalizations l10n, String priority) {
    return switch (priority) {
      'high' => l10n.str('work_order_priority_high'),
      'medium' => l10n.str('work_order_priority_medium'),
      'low' => l10n.str('work_order_priority_low'),
      _ => priority.isEmpty ? '-' : priority,
    };
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
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: AppColor.textHint(dialogContext),
                  ),
                )
              : Wrap(
                  spacing: 8.w,
                  runSpacing: 8.h,
                  children: [
                    for (var i = 0; i < selected.length; i++)
                      _attachmentThumb(
                        dialogContext,
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
        builder: (_) => WorkOrderDetailPage(order: order),
      ),
    );
  }

  /// 长按卡片：弹出操作菜单（查看详情 / 复制编号 / 复制SN / 删除）
  void _showActions(WorkOrderItem order) {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColor.surfaceContainer(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 24.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 拖动指示条
              Container(
                width: 36.w,
                height: 4.h,
                decoration: BoxDecoration(
                  color: AppColor.textHint(context).withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2.r),
                ),
              ),
              SizedBox(height: 16.h),
              // 当前工单摘要
              Row(
                children: [
                  PriorityBadge(priority: order.priority),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Text(
                      order.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColor.textPrimary(sheetContext),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12.h),
              Divider(color: AppColor.divider(sheetContext)),
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
          style: TextStyle(
            fontSize: 14.sp,
            color: AppColor.textSecondary(dialogContext),
          ),
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
        // 删除成功：所有 Tab 缓存失效，重载当前 Tab 与统计
        _invalidateCaches();
        await _load(reset: true);
        await _loadStats();
      } else {
        throw Exception(data is Map ? data['message'] : 'bad response');
      }
    } catch (e) {
      debugPrint('[WorkOrdersPage] delete failed: $e');
      if (!mounted) return;
      AppToast.show(context, l10n.str('work_order_delete_failed'),
          type: ToastType.error);
    }
  }

  /// 切换状态 Tab：状态驱动，优先读缓存，无缓存才请求
  void _onTabChanged(int index) {
    if (index < 0 || index >= _statusTabs.length) return;
    if (index == _tabIndex) return;
    // 使在途请求失效，避免旧 Tab 响应覆盖新 Tab 数据
    _reqSeq++;
    final cached = _tabCache[index];
    setState(() {
      _tabIndex = index;
      _statusFilter = _statusTabs[index];
      _page = 1;
      _loadingMore = false;
      if (cached != null) {
        // 有缓存：直接渲染，不发请求
        _items = cached;
        _hasMore = _tabHasMoreCache[index] ?? false;
        _loading = false;
        _refreshing = false;
      } else {
        // 无缓存：清空旧列表，走首次加载骨架屏
        _items = const [];
        _hasMore = true;
        _refreshing = false;
      }
    });
    if (cached == null) {
      _load(reset: true);
    }
  }

  /// Tab 文案：状态名 + 数量（统计加载中不显示括号）
  String _tabLabel(AppLocalizations l10n, int index) {
    final count = switch (index) {
      0 => _statTotal,
      1 => _statOpen,
      2 => _statInProgress,
      _ => _statResolved + _statClosed,
    };
    final label = switch (index) {
      0 => l10n.workOrderTabAll,
      1 => l10n.workOrderStatusPending,
      2 => l10n.workOrderStatusProcessing,
      _ => l10n.workOrderTabDone,
    };
    return count > 0 ? '$label ($count)' : label;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.helpWorkOrder),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(44.h),
          child: _buildStatusTabs(l10n),
        ),
      ),
      floatingActionButton: _buildSubmitFab(l10n),
      body: _buildBody(l10n),
    );
  }

  /// 自绘状态筛选 Tab 行：横向滚动胶囊 chip，选中态主题色高亮
  Widget _buildStatusTabs(AppLocalizations l10n) {
    return SizedBox(
      height: 44.h,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 7.h),
        itemCount: _statusTabs.length,
        separatorBuilder: (_, __) => SizedBox(width: 8.w),
        itemBuilder: (context, i) {
          final selected = i == _tabIndex;
          return Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(15.r),
            child: InkWell(
              onTap: () => _onTabChanged(i),
              borderRadius: BorderRadius.circular(15.r),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 14.w),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primary.withValues(alpha: 0.1)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(15.r),
                  border: Border.all(
                    color: selected
                        ? AppColors.primary.withValues(alpha: 0.4)
                        : AppColor.divider(context),
                  ),
                ),
                child: Text(
                  _tabLabel(l10n, i),
                  style: TextStyle(
                    fontSize: 13.sp,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected
                        ? AppColors.primary
                        : AppColor.textSecondary(context),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 自绘胶囊悬浮提交按钮：主题色渐变背景 + 阴影
  Widget _buildSubmitFab(AppLocalizations l10n) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16.r),
      child: InkWell(
        onTap: _showSubmitDialog,
        borderRadius: BorderRadius.circular(16.r),
        child: Ink(
          padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 12.h),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16.r),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.primaryLight, AppColors.primary],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.35),
                blurRadius: 12.r,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.edit_note_rounded, size: 20.sp, color: Colors.white),
              SizedBox(width: 6.w),
              Text(
                l10n.workOrderSubmit,
                style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    // 仅无数据首次加载显示整页骨架屏
    if (_loading) {
      return const PageSkeleton();
    }
    return Column(
      children: [
        // 已有数据时的刷新：顶部细进度条叠在旧列表上，不清空列表
        if (_refreshing) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: _items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.inbox_outlined,
                        size: 48.sp,
                        color: AppColor.textHint(context),
                      ),
                      SizedBox(height: 12.h),
                      Text(
                        l10n.workOrderEmpty,
                        style: TextStyle(
                          fontSize: 14.sp,
                          color: AppColor.textHint(context),
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _load(reset: true),
                  child: ListView.builder(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 88.h),
                    itemCount: _items.length + 1,
                    itemBuilder: (context, index) {
                      if (index == _items.length) {
                        return Padding(
                          padding: EdgeInsets.symmetric(vertical: 12.h),
                          child: Center(
                            child: _loadingMore
                                ? SizedBox(
                                    width: 20.w,
                                    height: 20.w,
                                    child: const CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Text(
                                    _hasMore
                                        ? l10n.str('work_order_loading_more')
                                        : l10n.str('work_order_no_more'),
                                    style: TextStyle(
                                      fontSize: 12.sp,
                                      color: AppColor.textHint(context),
                                    ),
                                  ),
                          ),
                        );
                      }
                      return Padding(
                        padding: EdgeInsets.only(bottom: 10.h),
                        child: _WorkOrderCard(
                          order: _items[index],
                          onTap: () => _openDetail(_items[index]),
                          onLongPress: () => _showActions(_items[index]),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

/// 工单模板兜底数据（与后端 /work-orders/templates 结构一致）
class WorkOrderTemplate {
  static const List<Map<String, dynamic>> fallback = [
    {
      'templateId': 'repair',
      'title': '设备故障',
      'description': '设备运行异常，需要检修',
      'priority': 'high',
    },
    {
      'templateId': 'maintenance',
      'title': '定期维护',
      'description': '设备定期保养维护',
      'priority': 'medium',
    },
    {
      'templateId': 'inspection',
      'title': '设备巡检',
      'description': '设备运行状态巡检',
      'priority': 'low',
    },
    {
      'templateId': 'installation',
      'title': '安装调试',
      'description': '设备安装与参数调试',
      'priority': 'medium',
    },
  ];
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

  /// 后端同时输出 camelCase 与 snake_case 字段，双兼容解析；
  /// 时间解析失败回退当前时间，避免整条数据丢失
  factory WorkOrderItem.fromJson(Map<String, dynamic> json) {
    return WorkOrderItem(
      id: json['id']?.toString() ?? '',
      title: (json['title'] ?? '').toString(),
      status: (json['status'] ?? 'open').toString(),
      priority: (json['priority'] ?? '').toString(),
      deviceSn: (json['deviceSn'] ?? json['device_sn'] ?? '').toString(),
      createdAt: _parseTime(json['createdAt'] ?? json['created_at']),
    );
  }

  static DateTime _parseTime(dynamic raw) {
    if (raw == null) return DateTime.now();
    return DateTime.tryParse(raw.toString()) ?? DateTime.now();
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
    final (statusColor, statusLabel) = _statusOf(context, l10n, order.status);
    return Material(
      color: AppColor.surfaceContainer(context),
      borderRadius: BorderRadius.circular(16.r),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(16.r),
        child: Container(
          padding: EdgeInsets.all(14.w),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(color: AppColor.divider(context)),
          ),
          child: Row(
            children: [
              // 优先级图标圆底
              PriorityBadge(priority: order.priority),
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
                        color: AppColor.textPrimary(context),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      '${order.deviceSn.isEmpty ? '' : '${order.deviceSn} · '}'
                      '${formatWorkOrderTime(order.createdAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: AppColor.textHint(context),
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

  (Color, String) _statusOf(
    BuildContext context,
    AppLocalizations l10n,
    String status,
  ) {
    return switch (status) {
      'open' => (AppColors.warning, l10n.workOrderStatusPending),
      'in_progress' => (AppColors.primary, l10n.workOrderStatusProcessing),
      'resolved' => (AppColors.successLight, l10n.workOrderStatusResolved),
      'closed' => (AppColor.textHint(context), l10n.workOrderStatusClosed),
      _ => (AppColor.textHint(context), status),
    };
  }
}

/// 优先级图标圆底徽章
class PriorityBadge extends StatelessWidget {
  final String priority;

  const PriorityBadge({super.key, required this.priority});

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
        destructive ? AppColors.error : AppColor.textPrimary(context);
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
String formatWorkOrderTime(DateTime time) {
  final t = time.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}';
}

/// 工单详情页（GET /work-orders/:id）
///
/// 展示：头部状态/优先级、完整字段、问题描述、处理结果、
/// 处理进度时间线、附件图片（点击放大）。
class WorkOrderDetailPage extends StatefulWidget {
  final WorkOrderItem order;

  const WorkOrderDetailPage({super.key, required this.order});

  @override
  State<WorkOrderDetailPage> createState() => _WorkOrderDetailPageState();
}

class _WorkOrderDetailPageState extends State<WorkOrderDetailPage> {
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
      debugPrint('[WorkOrderDetailPage] load failed: $e');
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
              style: TextStyle(
                fontSize: 14.sp,
                color: AppColor.textHint(context),
              ),
            ),
            SizedBox(height: 12.h),
            OutlinedButton(onPressed: _load, child: Text(l10n.retry)),
          ],
        ),
      );
    }
    final detail = _detail!;
    final (statusColor, statusLabel) =
        _detailStatusOf(context, l10n, detail.status);
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
                  color: AppColor.textPrimary(context),
                ),
              ),
              SizedBox(height: 6.h),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${l10n.workOrderNo}：#${detail.id}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: AppColor.textHint(context),
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () async {
                      await Clipboard.setData(
                          ClipboardData(text: detail.id));
                      if (context.mounted) {
                        AppToast.show(
                          context,
                          l10n.str('op_log_copied'),
                          type: ToastType.success,
                        );
                      }
                    },
                    borderRadius: BorderRadius.circular(8.r),
                    child: Padding(
                      padding: EdgeInsets.all(4.w),
                      child: Icon(
                        Icons.copy_rounded,
                        size: 16.sp,
                        color: AppColor.textHint(context),
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
              _InfoRow(
                label: l10n.workOrderPriority,
                value: _priorityLabel(l10n, detail.priority),
              ),
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
              _InfoRow(
                label: l10n.workOrderCreator,
                value: detail.creatorName.isEmpty ? '-' : detail.creatorName,
              ),
              SizedBox(height: 10.h),
              _InfoRow(
                label: l10n.workOrderAssignee,
                value: detail.assigneeName.isEmpty
                    ? l10n.str('work_order_no_assignee')
                    : detail.assigneeName,
              ),
              SizedBox(height: 10.h),
              _InfoRow(
                label: l10n.workOrderCreatedAt,
                value: formatWorkOrderTime(detail.createdAt),
              ),
              SizedBox(height: 10.h),
              _InfoRow(
                label: l10n.workOrderUpdatedAt,
                value: formatWorkOrderTime(detail.updatedAt),
              ),
              if (detail.slaDeadline != null) ...[
                SizedBox(height: 10.h),
                _InfoRow(
                  label: l10n.str('work_order_sla_deadline'),
                  value: formatWorkOrderTime(detail.slaDeadline!),
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
              color: AppColor.textSecondary(context),
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
                color: AppColor.textSecondary(context),
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

  (Color, String) _detailStatusOf(
    BuildContext context,
    AppLocalizations l10n,
    String status,
  ) {
    return switch (status) {
      'open' => (AppColors.warning, l10n.workOrderStatusPending),
      'in_progress' => (AppColors.primary, l10n.workOrderStatusProcessing),
      'resolved' => (AppColors.successLight, l10n.workOrderStatusResolved),
      'closed' => (AppColor.textHint(context), l10n.workOrderStatusClosed),
      _ => (AppColor.textHint(context), status),
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

/// 工单详情数据模型（GET /work-orders/:id 全字段，camel/snake 双兼容）
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
      id: json['id']?.toString() ?? '',
      title: (json['title'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      status: (json['status'] ?? 'open').toString(),
      priority: (json['priority'] ?? '').toString(),
      deviceSn: (json['deviceSn'] ?? json['device_sn'] ?? '').toString(),
      creatorName:
          (json['creatorName'] ?? json['creator_name'] ?? '').toString(),
      assigneeName:
          (json['assigneeName'] ?? json['assignee_name'] ?? '').toString(),
      templateType:
          (json['templateType'] ?? json['template_type'] ?? '').toString(),
      resolution: (json['resolution'] ?? '').toString(),
      slaDeadline: _tryParse(json['slaDeadline'] ?? json['sla_deadline']),
      createdAt:
          _tryParse(json['createdAt'] ?? json['created_at']) ?? DateTime.now(),
      updatedAt:
          _tryParse(json['updatedAt'] ?? json['updated_at']) ?? DateTime.now(),
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

  static DateTime? _tryParse(dynamic raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
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
      status: (json['status'] ?? '').toString(),
      operator: (json['operator'] ?? '').toString(),
      remark: (json['remark'] ?? '').toString(),
      timestamp: DateTime.tryParse((json['timestamp'] ?? '').toString()) ??
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
      name: (json['name'] ?? '').toString(),
      url: (json['url'] ?? '').toString(),
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
        color: AppColor.surfaceContainer(context),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: AppColor.divider(context)),
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
            style: TextStyle(fontSize: 13.sp, color: AppColor.textHint(context)),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13.sp,
              fontWeight: FontWeight.w500,
              color: AppColor.textPrimary(context),
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
                color: AppColor.textHint(context),
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
    final accent = PriorityBadge.colorOf(priority);
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
          Icon(PriorityBadge.iconOf(priority), size: 12.sp, color: accent),
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
      'closed' => (AppColor.textHint(context), l10n.workOrderStatusClosed),
      _ => (AppColor.textHint(context), event.status),
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
                      color: AppColor.divider(context),
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
                        formatWorkOrderTime(event.timestamp),
                        style: TextStyle(
                          fontSize: 11.sp,
                          color: AppColor.textHint(context),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    event.operator.isEmpty ? '-' : '操作人：${event.operator}',
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: AppColor.textHint(context),
                    ),
                  ),
                  if (event.remark.isNotEmpty) ...[
                    SizedBox(height: 2.h),
                    Text(
                      event.remark,
                      style: TextStyle(
                        fontSize: 12.sp,
                        height: 1.4,
                        color: AppColor.textSecondary(context),
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
            color: AppColor.surfaceHover(context),
            child: Icon(
              Icons.broken_image_outlined,
              size: 28.sp,
              color: AppColor.textHint(context),
            ),
          ),
        ),
      ),
    );
  }
}
