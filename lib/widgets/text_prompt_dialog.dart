import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A single-field prompt (a URL, a pasted document) that pops the trimmed
/// text on confirm and null on cancel. Empty input never confirms.
class TextPromptDialog extends StatefulWidget {
  final String title;
  final String hint;
  final String helper;

  /// Label of the confirm button.
  final String action;
  final bool multiline;

  /// Ignored when [multiline] (which forces the multiline keyboard).
  final TextInputType? keyboardType;

  const TextPromptDialog({
    super.key,
    required this.title,
    required this.hint,
    required this.helper,
    required this.action,
    this.multiline = false,
    this.keyboardType,
  });

  @override
  State<TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<TextPromptDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    Navigator.of(context).pop(text);
  }

  String? _clipboardNote;

  /// Imports straight from the clipboard without ever putting the text into
  /// the field. A big collections file pasted into a multiline TextField
  /// has to be laid out in full on the UI thread, which froze the desktop
  /// app ("Not Responding") for minutes.
  Future<void> _importClipboard() async {
    ClipboardData? data;
    try {
      data = await Clipboard.getData(Clipboard.kTextPlain);
    } catch (_) {
      data = null;
    }
    if (!mounted) return;
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      setState(() => _clipboardNote = 'The clipboard is empty.');
      return;
    }
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(widget.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              // Multiline (pasted documents): the clipboard button is the
              // primary path, so the field must not grab focus/keyboard.
              autofocus: !widget.multiline,
              keyboardType: widget.multiline
                  ? TextInputType.multiline
                  : (widget.keyboardType ?? TextInputType.text),
              maxLines: widget.multiline ? 10 : 1,
              minLines: widget.multiline ? 6 : 1,
              textInputAction: widget.multiline
                  ? TextInputAction.newline
                  : TextInputAction.done,
              onSubmitted: widget.multiline ? null : (_) => _submit(),
              decoration: InputDecoration(
                hintText: widget.hint,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(widget.helper, style: const TextStyle(fontSize: 12)),
            if (widget.multiline) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _importClipboard,
                icon: const Icon(Icons.content_paste_rounded),
                label: const Text('Use clipboard directly (best for big files)'),
              ),
              if (_clipboardNote != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _clipboardNote!,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _submit, child: Text(widget.action)),
      ],
    );
  }
}
