import 'package:flutter/material.dart';
import 'package:recipe_app/core/theme/app_spacing.dart';
import '../../data/models/unit_conversion.dart';

class UnitSelector extends StatefulWidget {
  final String ingredientText;
  final List<UnitEntry> compatibleUnits;
  final ValueChanged<String> onConvert;

  const UnitSelector({
    super.key,
    required this.ingredientText,
    required this.compatibleUnits,
    required this.onConvert,
  });

  static void show(
    BuildContext context, {
    required String ingredientText,
    required List<UnitEntry> compatibleUnits,
    required ValueChanged<String> onConvert,
  }) {
    showModalBottomSheet(
      context: context,
      builder: (_) => UnitSelector(
        ingredientText: ingredientText,
        compatibleUnits: compatibleUnits,
        onConvert: (converted) {
          onConvert(converted);
          Navigator.of(context).pop();
        },
      ),
    );
  }

  @override
  State<UnitSelector> createState() => _UnitSelectorState();
}

class _UnitSelectorState extends State<UnitSelector> {
  String? _selected;

  @override
  void initState() {
    super.initState();
    final r = UnitConverter.detectUnit(widget.ingredientText);
    if (r != null) {
      _selected = r.entry.singular.toLowerCase();
    }
  }

  void _select(UnitEntry u) {
    final singular = u.singular;
    setState(() => _selected = singular.toLowerCase());
    final converted = UnitConverter.convert(widget.ingredientText, singular);
    if (converted != null) {
      widget.onConvert(converted);
    }
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
          Text('Convert Unit', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            widget.ingredientText,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.md),
          const Divider(),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: widget.compatibleUnits.map((u) {
              final sel = _selected == u.singular.toLowerCase();
              return ChoiceChip(
                label: Text(u.singular),
                selected: sel,
                onSelected: sel ? null : (_) => _select(u),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
