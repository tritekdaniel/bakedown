import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recipe_app/core/theme/app_spacing.dart';
import '../../data/models/measurement.dart';
import '../providers/recipe_providers.dart';

class MemoryEditPopup extends ConsumerStatefulWidget {
  final String originalLine;
  final String displayText;

  const MemoryEditPopup({
    super.key,
    required this.originalLine,
    required this.displayText,
  });

  @override
  ConsumerState<MemoryEditPopup> createState() => _MemoryEditPopupState();
}

class _MemoryEditPopupState extends ConsumerState<MemoryEditPopup> {
  late TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _initialQuantity);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _initialQuantity {
    final m = Measurement.parse(widget.displayText);
    if (m != null) return Measurement.formatQuantity(m.quantity);
    return '';
  }

  void _apply() {
    final raw = _controller.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = 'Enter a quantity');
      return;
    }

    final parsed = double.tryParse(raw);
    if (parsed != null && parsed >= 0) {
      final original = widget.originalLine;
      final m = Measurement.parse(original);
      if (m != null) {
        final edited = m.toEditedString(parsed);
        ref.read(memoryEditsProvider.notifier).setEdit(original, edited);
      } else {
        ref.read(memoryEditsProvider.notifier).setEdit(original, raw);
      }
      Navigator.of(context).pop();
      return;
    }

    final frac = RegExp(r'^(\d+)\s*/\s*(\d+)$').firstMatch(raw);
    if (frac != null) {
      final num = int.parse(frac.group(1)!);
      final den = int.parse(frac.group(2)!);
      if (den > 0) {
        final parsedVal = num / den;
        final original = widget.originalLine;
        final m = Measurement.parse(original);
        if (m != null) {
          final edited = m.toEditedString(parsedVal);
          ref.read(memoryEditsProvider.notifier).setEdit(original, edited);
        }
        Navigator.of(context).pop();
        return;
      }
    }

    final mixed = RegExp(r'^(\d+)\s+(\d+)\s*/\s*(\d+)$').firstMatch(raw);
    if (mixed != null) {
      final whole = int.parse(mixed.group(1)!);
      final num = int.parse(mixed.group(2)!);
      final den = int.parse(mixed.group(3)!);
      if (den > 0) {
        final parsedVal = whole + num / den;
        final original = widget.originalLine;
        final m = Measurement.parse(original);
        if (m != null) {
          final edited = m.toEditedString(parsedVal);
          ref.read(memoryEditsProvider.notifier).setEdit(original, edited);
        }
        Navigator.of(context).pop();
        return;
      }
    }

    setState(() => _error = 'Invalid quantity');
  }

  void _revert() {
    ref.read(memoryEditsProvider.notifier).removeEdit(widget.originalLine);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasEdit = ref.watch(memoryEditsProvider).containsKey(widget.originalLine);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Edit Quantity', style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(
                widget.displayText,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _controller,
                autofocus: true,
                keyboardType: TextInputType.text,
                decoration: InputDecoration(
                  labelText: 'Quantity',
                  errorText: _error,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: hasEdit ? _revert : null,
                      child: const Text('Revert'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: _apply,
                      child: const Text('Apply'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
