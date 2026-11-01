import 'package:dart_quill_delta/dart_quill_delta.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'document_codec.dart';

/// Applies an AI suggestion only while the captured document and selection match.
bool applyInlineAiEdit(quill.QuillController controller,
    TextSelection selection, String snapshot, String markdown,
    {required bool replace}) {
  if (!selection.isValid ||
      selection.isCollapsed ||
      controller.selection != selection ||
      DocumentCodec.encode(controller.document) != snapshot) {
    return false;
  }
  final document = DocumentCodec.fromMarkdown(markdown);
  final plainResult = document.toPlainText().trimRight();
  if (plainResult.isEmpty) return false;
  final original = controller.document.toPlainText();
  if (selection.end > original.length - 1) return false;
  final ops = document.toDelta().toJson();
  final hasBlock = ops.any((op) =>
      (op['attributes'] as Map?)?.containsKey('list') == true ||
      (op['attributes'] as Map?)?.containsKey('header') == true ||
      (op['attributes'] as Map?)?.containsKey('blockquote') == true);
  if (hasBlock) {
    while (ops.isNotEmpty &&
        ops.last['attributes'] == null &&
        ops.last['insert'] is String &&
        (ops.last['insert'] as String).trim().isEmpty) {
      ops.removeLast();
    }
  }
  if (!hasBlock && ops.isNotEmpty) {
    final last = ops.last;
    final value = last['insert'];
    if (value is String && value.endsWith('\n')) {
      if (value.length == 1) {
        ops.removeLast();
      } else {
        last['insert'] = value.substring(0, value.length - 1);
      }
    }
  }
  final end = original.indexOf('\n', selection.end);
  final offset =
      replace ? selection.start : (end < 0 ? original.length - 1 : end);
  final prefix =
      !replace || (hasBlock && offset > 0 && original[offset - 1] != '\n')
          ? '\n'
          : '';
  final delta = Delta();
  if (prefix.isNotEmpty) delta.insert(prefix);
  for (final operation in Delta.fromJson(ops).operations) {
    delta.push(operation);
  }
  final insertedLength = prefix.length +
      ops.fold<int>(0, (length, op) {
        final value = op['insert'];
        return length + (value is String ? value.length : 1);
      });
  final consumeFollowingBreak = replace &&
      hasBlock &&
      selection.end < original.length - 1 &&
      original[selection.end] == '\n';
  controller.replaceText(
      offset,
      replace
          ? selection.end - selection.start + (consumeFollowingBreak ? 1 : 0)
          : 0,
      delta,
      TextSelection.collapsed(offset: offset + insertedLength),
      ignoreFocus: true);
  return true;
}
