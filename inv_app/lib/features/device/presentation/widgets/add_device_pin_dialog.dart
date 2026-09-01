import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// PIN input used when a scanned QR code does not contain a device PIN.
///
/// The dialog owns the input controller so its lifetime matches the dialog
/// route, and guards the short route-exit window against repeated actions.
class AddDevicePinDialog extends StatefulWidget {
  const AddDevicePinDialog({
    super.key,
    required this.title,
    required this.hintText,
    required this.invalidPinMessage,
    required this.cancelLabel,
    required this.confirmLabel,
  });

  final String title;
  final String hintText;
  final String invalidPinMessage;
  final String cancelLabel;
  final String confirmLabel;

  @override
  State<AddDevicePinDialog> createState() => _AddDevicePinDialogState();
}

class _AddDevicePinDialogState extends State<AddDevicePinDialog> {
  final _controller = TextEditingController();
  bool _isClosing = false;
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _close([String? result]) {
    if (_isClosing) return;
    _isClosing = true;
    Navigator.pop(context, result);
  }

  void _confirm() {
    final pin = _controller.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(pin)) {
      setState(() => _errorText = widget.invalidPinMessage);
      return;
    }
    _close(pin);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        maxLength: 6,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          hintText: widget.hintText,
          counterText: '',
          errorText: _errorText,
        ),
        onChanged: (_) {
          if (_errorText != null) setState(() => _errorText = null);
        },
      ),
      actions: [
        TextButton(
          onPressed: () => _close(),
          child: Text(widget.cancelLabel),
        ),
        TextButton(
          onPressed: _confirm,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
