import 'package:flutter/material.dart';
import '../../../../shared/widgets/tag_colors.dart';
import '../../data/models/recipe_model.dart';

class RecipeCard extends StatelessWidget {
  final RecipeModel recipe;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final bool dense;

  const RecipeCard({
    super.key,
    required this.recipe,
    required this.onTap,
    this.onDelete,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final difficultyColor = switch (recipe.difficulty?.toLowerCase()) {
      'easy' => cs.tertiary,
      'medium' => cs.secondary,
      'hard' => cs.error,
      _ => cs.primary,
    };

    return Card(
      margin: EdgeInsets.symmetric(horizontal: dense ? 0 : 12, vertical: 4),
      child: InkWell(
        onTap: onTap,
        onLongPress: onDelete,
        borderRadius: BorderRadius.circular(16),
        hoverColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.04),
        highlightColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Hero(
                tag: 'recipe_icon_${recipe.fileName}',
                child: CircleAvatar(
                  backgroundColor: cs.primaryContainer,
                  radius: 24,
                  child: Icon(Icons.receipt_long, color: cs.onPrimaryContainer, size: 24),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recipe.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        children: [
                        if (recipe.difficulty != null &&
                            recipe.difficulty!.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: difficultyColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              recipe.difficulty![0].toUpperCase() +
                                  recipe.difficulty!.substring(1),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: difficultyColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (recipe.prepTime != null &&
                            recipe.prepTime!.isNotEmpty) ...[
                          Icon(Icons.schedule, size: 15,
                              color: cs.primary.withValues(alpha: 0.8)),
                          const SizedBox(width: 4),
                          Text(
                            recipe.prepTime!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (recipe.servings != null) ...[
                          Icon(Icons.people, size: 15,
                              color: cs.primary.withValues(alpha: 0.8)),
                          const SizedBox(width: 4),
                          Text(
                            '${recipe.servings}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (recipe.tags.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: recipe.tags.take(3).map((t) {
                            final c = tagColor(t, theme.colorScheme);
                            return Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: c.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: c.withValues(alpha: 0.3),
                                    width: 0.5,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Icon(Icons.tag, size: 11, color: c),
                                    const SizedBox(width: 3),
                                    Padding(
                                      padding: const EdgeInsets.only(top: 1),
                                      child: Text(t, style: theme.textTheme.labelSmall?.copyWith(fontSize: 11, color: c, fontWeight: FontWeight.w600)),
                                    ),
                                  ],
                                ),
                              ),
                            );
                            }).toList(),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.only(top: dense ? 0 : 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onDelete != null)
                      IconButton(
                        icon: Icon(Icons.delete_outline, size: dense ? 16 : 20,
                            color: theme.colorScheme.error),
                        onPressed: onDelete,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                            minWidth: 24, minHeight: 24),
                        splashRadius: dense ? 14 : 18,
                      ),
                    Icon(Icons.chevron_right, size: dense ? 16 : 20,
                        color: cs.onSurfaceVariant),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
