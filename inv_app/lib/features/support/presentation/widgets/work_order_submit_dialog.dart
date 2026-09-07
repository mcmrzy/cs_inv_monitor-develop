import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';

import 'package:inv_app/core/theme/app_theme.dart';
import 'package:inv_app/core/widgets/app_toast.dart';
import 'package:inv_app/l10n/app_localizations.dart';

typedef WorkOrderImagePicker = Future<List<XFile>> Function();

class WorkOrderSubmitData {
  final String title;
  final String description;
  final String priority;
  final String templateType;
  final String deviceSn;
  final List<XFile> images;

  const WorkOrderSubmitData({
    required this.title,
    required this.description,
    required this.priority,
    required this.templateType,
    required this.deviceSn,
    required this.images,
  });
}

/// 工单提交弹窗。
///
/// 输入、选择和附件状态均由弹窗自身持有，确保 controller 与异步回调
/// 都不会越过弹窗的生命周期。
class WorkOrderSubmitDialog extends StatefulWidget {
  final List<Map<String, dynamic>> templates;
  final List<(String, String)> deviceOptions;
  final WorkOrderImagePicker? pickImages;

  const WorkOrderSubmitDialog({
    super.key,
    required this.templates,
    required this.deviceOptions,
    this.pickImages,
  });

  @override
  State<WorkOrderSubmitDialog> createState() => _WorkOrderSubmitDialogState();
}

class _WorkOrderSubmitDialogState extends State<WorkOrderSubmitDialog> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final List<XFile> _selectedImages = [];

  late String _selectedTemplate;
  String _selectedPriority = 'medium';
  String _selectedDeviceSn = '';
  bool _completed = false;
  bool _isPickingImages = false;

  @override
  void initState() {
    super.initState();
    _selectedTemplate = widget.templates.isNotEmpty
        ? (widget.templates.first['templateId'] ?? 'repair').toString()
        : 'repair';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.workOrderSubmit),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              maxLength: 50,
              decoration: InputDecoration(
                labelText: l10n.workOrderTitleLabel,
                hintText: l10n.workOrderTitleHint,
              ),
            ),
            SizedBox(height: 8.h),
            TextField(
              controller: _descriptionController,
              maxLines: 4,
              maxLength: 500,
              decoration: InputDecoration(
                labelText: l10n.workOrderDescLabel,
                hintText: l10n.workOrderDescHint,
                alignLabelWithHint: true,
              ),
            ),
            SizedBox(height: 12.h),
            _selectRow(
              icon: Icons.category_rounded,
              label: l10n.str('work_order_template'),
              value: _templateTitle(_selectedTemplate),
              onTap: _selectTemplate,
            ),
            SizedBox(height: 8.h),
            _selectRow(
              icon: Icons.flag_rounded,
              label: l10n.workOrderPriority,
              value: _priorityLabel(l10n, _selectedPriority),
              onTap: _selectPriority,
            ),
            SizedBox(height: 8.h),
            _selectRow(
              icon: Icons.devices_other_rounded,
              label: l10n.str('work_order_select_device'),
              value: _selectedDeviceSn.isEmpty
                  ? l10n.str('work_order_no_device')
                  : _selectedDeviceSn,
              onTap: _selectDevice,
            ),
            SizedBox(height: 12.h),
            _buildAttachmentPicker(l10n),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _completed ? null : _cancel,
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _completed ? null : () => _submit(l10n),
          child: Text(l10n.workOrderSubmit),
        ),
      ],
    );
  }

  void _cancel() {
    if (_completed) return;
    _completed = true;
    Navigator.pop(context);
  }

  void _submit(AppLocalizations l10n) {
    if (_completed) return;
    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();
    if (title.isEmpty || description.isEmpty) {
      AppToast.show(
        context,
        l10n.str('work_order_required'),
        type: ToastType.info,
      );
      return;
    }

    _completed = true;
    Navigator.pop(
      context,
      WorkOrderSubmitData(
        title: title,
        description: description,
        priority: _selectedPriority,
        templateType: _selectedTemplate,
        deviceSn: _selectedDeviceSn,
        images: List.unmodifiable(_selectedImages),
      ),
    );
  }

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

  Future<void> _selectTemplate() async {
    final picked = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(
          AppLocalizations.of(dialogContext)!.str('work_order_template'),
        ),
        children: [
          for (final template in widget.templates)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(
                dialogContext,
                (template['templateId'] ?? '').toString(),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (template['title'] ?? '').toString(),
                          style: TextStyle(
                            fontSize: 14.sp,
                            fontWeight:
                                (template['templateId'] ?? '') ==
                                    _selectedTemplate
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                        ),
                        if ((template['description'] ?? '')
                            .toString()
                            .isNotEmpty)
                          Text(
                            (template['description'] ?? '').toString(),
                            style: TextStyle(
                              fontSize: 12.sp,
                              color: AppColor.textHint(dialogContext),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if ((template['templateId'] ?? '') == _selectedTemplate)
                    Icon(
                      Icons.check_rounded,
                      size: 16.sp,
                      color: AppColors.primary,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
    if (!mounted || picked == null) return;
    setState(() {
      _selectedTemplate = picked;
      final template = widget.templates.firstWhere(
        (item) => (item['templateId'] ?? '') == picked,
        orElse: () => const {},
      );
      final priority = (template['priority'] ?? '').toString();
      if (priority.isNotEmpty) _selectedPriority = priority;
    });
  }

  Future<void> _selectPriority() async {
    final l10n = AppLocalizations.of(context)!;
    final picked = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(l10n.workOrderPriority),
        children: [
          for (final priority in const ['high', 'medium', 'low'])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, priority),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _priorityLabel(l10n, priority),
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: priority == _selectedPriority
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (priority == _selectedPriority)
                    Icon(
                      Icons.check_rounded,
                      size: 16.sp,
                      color: AppColors.primary,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
    if (!mounted || picked == null) return;
    setState(() => _selectedPriority = picked);
  }

  Future<void> _selectDevice() async {
    final l10n = AppLocalizations.of(context)!;
    final picked = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(l10n.str('work_order_select_device')),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, ''),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.str('work_order_no_device'),
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: _selectedDeviceSn.isEmpty
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                  ),
                ),
                if (_selectedDeviceSn.isEmpty)
                  Icon(
                    Icons.check_rounded,
                    size: 16.sp,
                    color: AppColors.primary,
                  ),
              ],
            ),
          ),
          for (final (sn, name) in widget.deviceOptions)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, sn),
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
                            fontWeight: sn == _selectedDeviceSn
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                        ),
                        Text(
                          sn,
                          style: TextStyle(
                            fontSize: 11.sp,
                            color: AppColor.textHint(dialogContext),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (sn == _selectedDeviceSn)
                    Icon(
                      Icons.check_rounded,
                      size: 16.sp,
                      color: AppColors.primary,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
    if (!mounted || picked == null) return;
    setState(() => _selectedDeviceSn = picked);
  }

  Widget _buildAttachmentPicker(AppLocalizations l10n) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: _selectedImages.isEmpty
              ? Text(
                  l10n.workOrderAttachHint,
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: AppColor.textHint(context),
                  ),
                )
              : Wrap(
                  spacing: 8.w,
                  runSpacing: 8.h,
                  children: [
                    for (var index = 0;
                        index < _selectedImages.length;
                        index++)
                      _attachmentThumb(index),
                  ],
                ),
        ),
        TextButton.icon(
          onPressed: _selectedImages.length >= 5 || _isPickingImages
              ? null
              : () => _pickImages(l10n),
          icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
          label: Text(l10n.workOrderAddImage),
        ),
      ],
    );
  }

  Widget _attachmentThumb(int index) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8.r),
          child: Image.file(
            File(_selectedImages[index].path),
            width: 52.w,
            height: 52.w,
            fit: BoxFit.cover,
          ),
        ),
        Positioned(
          top: -6.h,
          right: -6.w,
          child: GestureDetector(
            onTap: () => setState(() => _selectedImages.removeAt(index)),
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

  Future<void> _pickImages(AppLocalizations l10n) async {
    if (_isPickingImages || _completed) return;
    setState(() => _isPickingImages = true);
    try {
      final picked = widget.pickImages != null
          ? await widget.pickImages!()
          : await ImagePicker().pickMultiImage(
              maxWidth: 1600,
              maxHeight: 1600,
              imageQuality: 85,
            );
      if (!mounted || _completed || picked.isEmpty) return;
      final remaining = 5 - _selectedImages.length;
      if (picked.length > remaining) {
        AppToast.show(
          context,
          l10n.workOrderAttachHint,
          type: ToastType.info,
        );
      }
      setState(() => _selectedImages.addAll(picked.take(remaining)));
    } finally {
      if (mounted) {
        setState(() => _isPickingImages = false);
      }
    }
  }

  String _templateTitle(String id) {
    for (final template in widget.templates) {
      if ((template['templateId'] ?? '') == id) {
        return (template['title'] ?? id).toString();
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
}
