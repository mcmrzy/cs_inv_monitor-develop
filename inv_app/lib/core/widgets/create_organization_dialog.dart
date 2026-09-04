import 'package:flutter/material.dart';
import 'package:inv_app/core/entities/organization.dart';

typedef CreateOrganization = Future<Organization> Function({
  required String name,
  String? description,
});

/// Dialog content that owns and disposes its input controllers.
class CreateOrganizationDialog extends StatefulWidget {
  final CreateOrganization onSubmit;

  const CreateOrganizationDialog({
    super.key,
    required this.onSubmit,
  });

  @override
  State<CreateOrganizationDialog> createState() =>
      _CreateOrganizationDialogState();
}

class _CreateOrganizationDialogState extends State<CreateOrganizationDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _descriptionController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;

    final name = _nameController.text.trim();
    final description = _descriptionController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入组织名称')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final organization = await widget.onSubmit(
        name: name,
        description: description.isEmpty ? null : description,
      );
      if (!mounted) return;
      Navigator.pop(context, organization);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('创建失败：$error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isSubmitting,
      child: AlertDialog(
        title: const Text('创建新组织'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                enabled: !_isSubmitting,
                decoration: const InputDecoration(
                  labelText: '组织名称',
                  hintText: '请输入组织名称',
                  prefixIcon: Icon(Icons.business),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _descriptionController,
                enabled: !_isSubmitting,
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
            onPressed: _isSubmitting ? null : () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: _isSubmitting ? null : _submit,
            child: _isSubmitting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('创建'),
          ),
        ],
      ),
    );
  }
}
