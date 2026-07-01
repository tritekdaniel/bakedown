import 'package:flutter/material.dart';
import 'package:recipe_app/core/theme/app_spacing.dart';

class ScaleSelector extends StatefulWidget {
  final double currentFactor;
  final ValueChanged<double> onSelected;

  const ScaleSelector({
    super.key,
    required this.currentFactor,
    required this.onSelected,
  });

  static void show(BuildContext context, {
    required double currentFactor,
    required ValueChanged<double> onSelected,
  }) {
    showModalBottomSheet(
      context: context,
      builder: (_) => ScaleSelector(
        currentFactor: currentFactor,
        onSelected: (factor) {
          onSelected(factor);
          Navigator.of(context).pop();
        },
      ),
    );
  }

  @override
  State<ScaleSelector> createState() => _ScaleSelectorState();
}

class _ScaleSelectorState extends State<ScaleSelector> {
  late final TextEditingController _controller;
  String? _error;

  static const _presets = [0.5, 1.0, 2.0, 3.0];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: _formatFactor(widget.currentFactor),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatFactor(double f) {
    if (f == 0.5) return '0.5';
    if (f == f.roundToDouble()) return f.toInt().toString();
    return f.toStringAsFixed(1);
  }

  String _presetLabel(double f) {
    return switch (f) {
      0.5 => '½×',
      1.0 => '1×',
      2.0 => '2×',
      3.0 => '3×',
      _ => '${_formatFactor(f)}×',
    };
  }

  void _selectPreset(double f) {
    _controller.text = _formatFactor(f);
    setState(() => _error = null);
    widget.onSelected(f);
  }

  void _applyCustom() {
    final raw = _controller.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = 'Enter a number');
      return;
    }
    final f = double.tryParse(raw);
    if (f == null || f <= 0) {
      setState(() => _error = 'Enter a positive number');
      return;
    }
    setState(() => _error = null);
    widget.onSelected(f);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final bottomPad = AppSpacing.lg + MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        bottomPad,
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
          Text('Scale Ingredients', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: _presets.map((p) {
              final selected = p == widget.currentFactor;
              return ChoiceChip(
                label: Text(_presetLabel(p)),
                selected: selected,
                onSelected: (_) => _selectPreset(p),
              );
            }).toList(),
          ),
          const SizedBox(height: AppSpacing.md),
          const Divider(),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Custom factor',
                    errorText: _error,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton(
                onPressed: _applyCustom,
                child: const Text('Apply'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
