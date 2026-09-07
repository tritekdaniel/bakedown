import 'dart:io' if (dart.library.html) 'package:recipe_app/shared/stubs/io_stub.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/models/recipe_model.dart';
import '../../data/models/measurement.dart';
import '../../../../shared/widgets/tag_colors.dart';
import '../providers/recipe_providers.dart';
import 'memory_edit_popup.dart';
import 'package:recipe_app/core/theme/app_spacing.dart';
import '../../data/models/unit_conversion.dart';
import 'unit_selector.dart';

String _processFractions(String text) {
  const fractions = [
    (r'1/2', '\u00BD'),
    (r'1/3', '\u2153'),
    (r'2/3', '\u2154'),
    (r'1/4', '\u00BC'),
    (r'3/4', '\u00BE'),
    (r'1/8', '\u215B'),
    (r'3/8', '\u215C'),
    (r'5/8', '\u215D'),
    (r'7/8', '\u215E'),
  ];
  var result = text;
  for (final f in fractions) {
    result = result.replaceAllMapped(
      RegExp(r'(?<!\d)(\d+\s+)?' + f.$1 + r'(?!\d)'),
      (m) => '${m.group(1) ?? ''}${f.$2}',
    );
  }
  return result;
}

class MarkdownReader extends ConsumerStatefulWidget {
  final RecipeModel recipe;
  final bool embedded;
  final String rootPath;
  final Future<String> Function(String folder, String fileName)? imagePathFor;

  const MarkdownReader({
    super.key,
    required this.recipe,
    this.embedded = false,
    this.rootPath = '',
    this.imagePathFor,
  });

  @override
  ConsumerState<MarkdownReader> createState() => _MarkdownReaderState();
}

final _checkboxLineRe = RegExp(r'^- \[([ xX])\] (.+)$');
final _h2Re = RegExp(r'^## ');

class _MarkdownReaderState extends ConsumerState<MarkdownReader> {
  final Map<String, bool> _checkboxStates = {};

  @override
  void initState() {
    super.initState();
    _initCheckboxes();
  }

  @override
  void didUpdateWidget(MarkdownReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.recipe != widget.recipe) {
      _checkboxStates.clear();
      _initCheckboxes();
    }
  }

  void _initCheckboxes() {
    for (final line in widget.recipe.rawBody.split('\n')) {
      final match = _checkboxLineRe.firstMatch(line);
      if (match != null) {
        final key = match.group(2)!.trim();
        _checkboxStates[key] = match.group(1)!.toLowerCase() == 'x';
      }
    }
  }

  double get _padding => widget.embedded ? 16 : 24;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final recipe = widget.recipe;
    final hasMeta = recipe.prepTime?.isNotEmpty == true ||
        recipe.cookTime?.isNotEmpty == true ||
        recipe.totalTime?.isNotEmpty == true ||
        recipe.servings != null ||
        recipe.difficulty?.isNotEmpty == true ||
        recipe.source?.isNotEmpty == true ||
        recipe.created?.isNotEmpty == true;

    final hasTagsOrDifficulty = recipe.tags.isNotEmpty || recipe.difficulty?.isNotEmpty == true;

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: _padding, vertical: _padding),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SelectionArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Hero(
                      tag: 'reader_icon_${recipe.fileName}',
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.menu_book,
                            color: colorScheme.onPrimaryContainer, size: 22),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        recipe.title,
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                if (hasMeta || hasTagsOrDifficulty) ...[
                  const SizedBox(height: 20),
                  _MetadataRow(recipe: recipe),
                ],
                if (recipe.images.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _AttachedImages(
                    recipe: recipe,
                    rootPath: widget.rootPath,
                    imagePathFor: widget.imagePathFor,
                  ),
                ],
                const SizedBox(height: 20),
                Divider(color: colorScheme.outlineVariant, height: 1),
                const SizedBox(height: 20),
                ..._buildSections(theme, colorScheme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSections(ThemeData theme, ColorScheme colorScheme) {
    final sections = _splitSections(widget.recipe.rawBody);
    final widgets = <Widget>[];
    final scaleFactor = ref.watch(scaleFactorProvider);
    final memoryEdits = ref.watch(memoryEditsProvider);
    final unitConversions = ref.watch(unitConversionProvider);

    for (final section in sections) {
      final sectionWidgets = <Widget>[];
      final checkboxLines = <_CheckboxLine>[];
      final otherLines = <String>[];

      for (final line in section.lines) {
        final match = _checkboxLineRe.firstMatch(line);
        if (match != null) {
          checkboxLines.add(_CheckboxLine(
            key: match.group(2)!.trim(),
            originalText: match.group(2)!.trim(),
            initialChecked: match.group(1)!.toLowerCase() == 'x',
          ));
        } else {
          otherLines.add(line);
        }
      }

      final body = otherLines.join('\n').trim();

      if (section.header.isNotEmpty || body.isNotEmpty || checkboxLines.isEmpty) {
        final sectionMd = StringBuffer();
        if (section.header.isNotEmpty) {
          sectionMd.writeln(section.header);
        }
        if (body.isNotEmpty) {
          sectionMd.writeln(body);
        }
        final rendered = sectionMd.toString().trim();
        if (rendered.isNotEmpty) {
          sectionWidgets.add(GptMarkdownTheme(
            gptThemeData: GptMarkdownThemeData(
              brightness: theme.brightness,
              h2: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
                height: 1.5,
              ),
              h3: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            child: GptMarkdown(
              _processFractions(rendered),
              style: theme.textTheme.bodyLarge,
            ),
          ));
        }
      }

      for (final cl in checkboxLines) {
        final isChecked = _checkboxStates[cl.key] ?? cl.initialChecked;
        final isEdited = memoryEdits.containsKey(cl.originalText);
        final isConverted = unitConversions.containsKey(cl.originalText);
        final showIndent = isEdited || isConverted;

        String displayText;
        if (isEdited) {
          displayText = memoryEdits[cl.originalText]!;
        } else if (isConverted) {
          displayText = unitConversions[cl.originalText]!;
        } else if (scaleFactor != 1.0) {
          final m = Measurement.parse(cl.originalText);
          displayText = m != null ? m.toScaledString(scaleFactor) : cl.originalText;
        } else {
          displayText = cl.originalText;
        }

        sectionWidgets.add(
          Container(
            decoration: showIndent
                ? BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: colorScheme.primary,
                        width: 3,
                      ),
                    ),
                  )
                : null,
            padding: EdgeInsets.only(
              left: showIndent ? AppSpacing.sm : 0,
              top: 2,
              bottom: 2,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: isChecked,
                    onChanged: (val) {
                      setState(() => _checkboxStates[cl.key] = val ?? false);
                    },
                    semanticLabel: isChecked ? 'Checked' : 'Unchecked',
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                if (showIndent)
                  GestureDetector(
                    onTap: isEdited
                        ? () => _showEditPopup(cl.originalText, displayText)
                        : () => _showUnitSelector(cl.originalText),
                    child: Container(
                      width: 22,
                      height: 22,
                      margin: const EdgeInsets.only(right: AppSpacing.xs),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: colorScheme.primary.withValues(alpha: 0.25),
                          width: 0.5,
                        ),
                      ),
                      child: Icon(
                        isEdited ? Icons.edit_outlined : Icons.swap_horiz,
                        size: 13,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                Expanded(
                  child: GestureDetector(
                    onLongPress: () => _showEditPopup(cl.originalText, displayText),
                    onSecondaryTap: () => _showEditPopup(cl.originalText, displayText),
                    child: Text(
                      _processFractions(displayText),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        decoration: isChecked ? TextDecoration.lineThrough : null,
                        color: isChecked
                            ? theme.colorScheme.onSurfaceVariant
                            : showIndent
                                ? colorScheme.primary
                                : null,
                      ),
                    ),
                  ),
                ),
                if (isConverted)
                  GestureDetector(
                    onTap: () => _undoUnitConversion(cl.originalText),
                    child: Container(
                      width: 22,
                      height: 22,
                      margin: const EdgeInsets.only(left: AppSpacing.xs),
                      decoration: BoxDecoration(
                        color: colorScheme.error.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: colorScheme.error.withValues(alpha: 0.25),
                          width: 0.5,
                        ),
                      ),
                      child: Icon(
                        Icons.undo,
                        size: 13,
                        color: colorScheme.error,
                      ),
                    ),
                  )
                else
                  GestureDetector(
                    onTap: () => _showUnitSelector(cl.originalText),
                    child: Container(
                      width: 22,
                      height: 22,
                      margin: const EdgeInsets.only(left: AppSpacing.xs),
                      decoration: BoxDecoration(
                        color: colorScheme.secondary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: colorScheme.secondary.withValues(alpha: 0.25),
                          width: 0.5,
                        ),
                      ),
                      child: Icon(
                        Icons.swap_horiz,
                        size: 13,
                        color: colorScheme.secondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      }

      if (sectionWidgets.isNotEmpty) {
        if (widgets.isNotEmpty) {
          widgets.add(const SizedBox(height: AppSpacing.md));
        }
        widgets.addAll(sectionWidgets);
      }
    }

    return widgets;
  }

  void _showEditPopup(String originalText, String displayText) {
    showModalBottomSheet(
      context: context,
      builder: (_) => MemoryEditPopup(
        originalLine: originalText,
        displayText: displayText,
      ),
    );
  }

  void _showUnitSelector(String originalText) {
    final entries = UnitConverter.compatibleUnitEntries(originalText);
    if (entries.isEmpty) return;

    UnitSelector.show(
      context,
      ingredientText: originalText,
      compatibleUnits: entries,
      onConvert: (converted) {
        ref.read(unitConversionProvider.notifier).setConversion(
          originalText,
          converted,
        );
      },
    );
  }

  void _undoUnitConversion(String originalText) {
    ref.read(unitConversionProvider.notifier).removeConversion(originalText);
  }

  List<_Section> _splitSections(String body) {
    final lines = body.split('\n');
    final sections = <_Section>[];
    var currentHeader = '';
    var currentLines = <String>[];

    for (final line in lines) {
      if (_h2Re.hasMatch(line)) {
        if (currentHeader.isNotEmpty || currentLines.isNotEmpty) {
          sections.add(_Section(header: currentHeader, lines: List.from(currentLines)));
        }
        currentHeader = line;
        currentLines = [];
      } else {
        currentLines.add(line);
      }
    }

    if (currentHeader.isNotEmpty || currentLines.isNotEmpty) {
      sections.add(_Section(header: currentHeader, lines: List.from(currentLines)));
    }

    return sections;
  }
}



class _Section {
  final String header;
  final List<String> lines;
  const _Section({required this.header, required this.lines});
}

class _CheckboxLine {
  final String key;
  final String originalText;
  final bool initialChecked;
  const _CheckboxLine({
    required this.key,
    required this.originalText,
    required this.initialChecked,
  });
}

class _MetadataRow extends StatelessWidget {
  final RecipeModel recipe;
  const _MetadataRow({required this.recipe});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final items = <_MetaChipData>[];

    if (recipe.prepTime?.isNotEmpty == true) {
      items.add(_MetaChipData(Icons.timer_outlined, recipe.prepTime!));
    }
    if (recipe.cookTime?.isNotEmpty == true) {
      items.add(_MetaChipData(Icons.local_fire_department_outlined, recipe.cookTime!));
    }
    if (recipe.totalTime?.isNotEmpty == true) {
      items.add(_MetaChipData(Icons.schedule_outlined, recipe.totalTime!));
    }
    if (recipe.servings != null) {
      items.add(_MetaChipData(Icons.people_outline, '${recipe.servings}'));
    }
    if (recipe.source?.isNotEmpty == true) {
      items.add(_MetaChipData(Icons.link, recipe.source!, isLink: true));
    }
    if (recipe.created?.isNotEmpty == true) {
      items.add(_MetaChipData(Icons.calendar_today, recipe.created!));
    }

    final difficultyColor = switch (recipe.difficulty?.toLowerCase()) {
      'easy' => colorScheme.tertiary,
      'medium' => colorScheme.secondary,
      'hard' => colorScheme.error,
      _ => colorScheme.primary,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (items.isNotEmpty || recipe.difficulty?.isNotEmpty == true)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...items.map((d) => _MetaChip(
                    data: d,
                    color: d.isLink ? colorScheme.tertiary : colorScheme.primary,
                    onTap: d.isLink ? () => _launchUrl(d.value) : null,
                  )),
              if (recipe.difficulty?.isNotEmpty == true)
                _DifficultyChip(
                  difficulty: recipe.difficulty![0].toUpperCase() + recipe.difficulty!.substring(1),
                  color: difficultyColor,
                ),
            ],
          ),
        if (recipe.tags.isNotEmpty) ...[
          if (items.isNotEmpty || recipe.difficulty?.isNotEmpty == true)
            const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: recipe.tags
                  .map((t) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _TagChip(label: t),
                      ))
                  .toList(),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _MetaChipData {
  final IconData icon;
  final String value;
  final bool isLink;
  const _MetaChipData(this.icon, this.value, {this.isLink = false});
}

class _MetaChip extends StatelessWidget {
  final _MetaChipData data;
  final Color color;
  final VoidCallback? onTap;

  const _MetaChip({required this.data, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 20, height: 20,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(data.icon, size: 13, color: color),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                data.value,
                style: theme.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DifficultyChip extends StatelessWidget {
  final String difficulty;
  final Color color;

  const _DifficultyChip({required this.difficulty, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 20, height: 20,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(Icons.restaurant_outlined, size: 13, color: color),
          ),
          const SizedBox(width: 6),
          Text(
            difficulty,
            style: theme.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String label;

  const _TagChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = tagColor(label, theme.colorScheme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.tag, size: 13, color: c),
          const SizedBox(width: 4),
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(label, style: theme.textTheme.labelSmall?.copyWith(color: c, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _AttachedImages extends StatefulWidget {
  final RecipeModel recipe;
  final String rootPath;
  final Future<String> Function(String folder, String fileName)? imagePathFor;

  const _AttachedImages({
    super.key,
    required this.recipe,
    this.rootPath = '',
    this.imagePathFor,
  });

  @override
  State<_AttachedImages> createState() => _AttachedImagesState();
}

class _AttachedImagesState extends State<_AttachedImages> {
  late Future<List<String>> _pathsFuture;

  @override
  void initState() {
    super.initState();
    _initFuture();
  }

  @override
  void didUpdateWidget(covariant _AttachedImages oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.recipe != widget.recipe || oldWidget.imagePathFor != widget.imagePathFor) {
      _initFuture();
    }
  }

  void _initFuture() {
    if (widget.imagePathFor != null) {
      final folder = widget.recipe.folder;
      final images = widget.recipe.images;
      _pathsFuture = Future.wait(images.map((img) => widget.imagePathFor!(folder, img)));
    } else {
      _pathsFuture = Future.value([]);
    }
  }

  Widget _buildImageWidget(String imagePath, BoxFit fit) {
    if (imagePath.startsWith('data:') || imagePath.startsWith('blob:') || imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
      return Image.network(imagePath, fit: fit,
          errorBuilder: (c, e, s) => const Icon(Icons.broken_image));
    }
    if (kIsWeb) {
      if (imagePath.startsWith('http')) {
        return Image.network(imagePath, fit: fit,
            errorBuilder: (c, e, s) => const Icon(Icons.broken_image));
      }
      return const Icon(Icons.broken_image);
    }
    return Image.file(File(imagePath) as dynamic, fit: fit,
        errorBuilder: (c, e, s) => const Icon(Icons.broken_image));
  }

  void _showFullScreenImage(BuildContext context, String imagePath) {
    final cs = Theme.of(context).colorScheme;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: cs.surface,
          appBar: AppBar(
            backgroundColor: cs.surface,
            systemOverlayStyle: SystemUiOverlayStyle(
              statusBarIconBrightness: cs.brightness == Brightness.light ? Brightness.dark : Brightness.light,
            ),
          ),
          body: Center(
            child: InteractiveViewer(
              panEnabled: true,
              minScale: 0.5,
              maxScale: 4.0,
              child: _buildImageWidget(imagePath, BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final folder = widget.recipe.folder;
    final images = widget.recipe.images;

    if (widget.imagePathFor != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Attached Images', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          FutureBuilder<List<String>>(
            future: _pathsFuture,
            builder: (context, snapshot) {
              final paths = snapshot.data ?? [];
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(images.length, (i) {
                  final imagePath = i < paths.length && paths[i].isNotEmpty
                      ? paths[i]
                      : null;
                  return GestureDetector(
                    onTap: imagePath != null
                        ? () => _showFullScreenImage(context, imagePath)
                        : null,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: theme.colorScheme.outlineVariant),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: imagePath != null
                            ? _buildImageWidget(imagePath, BoxFit.cover)
                            : Container(
                                color: theme.colorScheme.surfaceContainerHighest,
                                child: Icon(Icons.broken_image, color: theme.colorScheme.onSurfaceVariant),
                              ),
                      ),
                    ),
                  );
                }),
              );
            },
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Attached Images', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: images.map((img) {
            final imagePath = p.join(widget.rootPath, folder, img);
            return GestureDetector(
              onTap: () => _showFullScreenImage(context, imagePath),
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: _buildImageWidget(imagePath, BoxFit.cover),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
