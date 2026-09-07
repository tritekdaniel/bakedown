import 'package:yaml/yaml.dart';
import 'package:path/path.dart' as p;

class RecipeModel {
  final String title;
  final String? prepTime;
  final String? cookTime;
  final String? totalTime;
  final int? servings;
  final String? difficulty;
  final List<String> tags;
  final String? source;
  final String? created;
  final String? modified;
  final List<String> images;
  final String rawFrontmatter;
  final String rawBody;
  final String fullContent;
  final String fileName;
  final String folder;

  RecipeModel({
    required this.title,
    this.prepTime,
    this.cookTime,
    this.totalTime,
    this.servings,
    this.difficulty,
    this.tags = const [],
    this.source,
    this.created,
    this.modified,
    this.images = const [],
    this.rawFrontmatter = '',
    this.rawBody = '',
    this.fullContent = '',
    this.fileName = '',
    this.folder = '',
  });

  factory RecipeModel.fromMarkdown(String content,
      {String fileName = '', String folder = ''}) {
    content = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (content.startsWith('\uFEFF')) content = content.substring(1);

    String frontmatterRaw = '';
    String body = content;

    final lines = content.split('\n');
    if (lines.isNotEmpty && lines.first.trim() == '---') {
      final closingIndex = lines.indexWhere((l) => l.trim() == '---', 1);
      if (closingIndex > 0) {
        frontmatterRaw = lines.sublist(1, closingIndex).join('\n');
        body = lines.sublist(closingIndex + 1).join('\n');
      }
    }

    String title = '';
    String? prepTime;
    String? cookTime;
    String? totalTime;
    int? servings;
    String? difficulty;
    List<String> tags = [];
    String? source;
    String? created;
    String? modified;
    List<String> images = [];

    if (frontmatterRaw.isNotEmpty) {
      try {
        final yaml = loadYaml(frontmatterRaw);
        if (yaml is YamlMap) {
          String? _s(dynamic v) => v?.toString();
          title = _s(yaml['title']) ?? '';
          prepTime = _s(yaml['prep_time']);
          cookTime = _s(yaml['cook_time']);
          totalTime = _s(yaml['total_time']);
          final sRaw = yaml['servings'];
          if (sRaw is int) {
            servings = sRaw;
          } else if (sRaw is String) {
            final firstNum = RegExp(r'\d+').firstMatch(sRaw);
            if (firstNum != null) servings = int.tryParse(firstNum.group(0)!);
          }
          difficulty = _s(yaml['difficulty']);
          source = _s(yaml['source']);
          created = _s(yaml['created']);
          modified = _s(yaml['modified']);
          final tagsRaw = yaml['tags'];
          if (tagsRaw is YamlList) {
            tags = tagsRaw.map((e) => e.toString().toLowerCase().trim()).where((e) => e.isNotEmpty).toList();
          } else if (tagsRaw is String) {
            tags = tagsRaw.split(',').map((e) => e.trim().toLowerCase()).where((e) => e.isNotEmpty).toList();
          }
          final imagesRaw = yaml['images'];
          if (imagesRaw is YamlList) {
            images = imagesRaw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
          } else if (imagesRaw is String) {
            images = imagesRaw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
          }
        }
      } catch (_) {}
    }

    if (title.isEmpty) {
      title = fileName
          .replaceFirst(RegExp(r'\.md$', caseSensitive: false), '')
          .replaceAll('_', ' ')
          .replaceAll('-', ' ')
          .split(' ')
          .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
          .join(' ');
    }

    return RecipeModel(
      title: title,
      prepTime: prepTime,
      cookTime: cookTime,
      totalTime: totalTime,
      servings: servings,
      difficulty: difficulty,
      tags: tags,
      source: source,
      created: created,
      modified: modified,
      images: images,
      rawFrontmatter: frontmatterRaw,
      rawBody: body,
      fullContent: content,
      fileName: fileName,
      folder: folder,
    );
  }

  String toMarkdown() {
    final buf = StringBuffer();
    buf.writeln('---');
    if (rawFrontmatter.trim().isNotEmpty) buf.writeln(rawFrontmatter.trim());
    buf.writeln('---');
    buf.writeln(rawBody);
    return buf.toString();
  }

  String get filePath => p.join(folder, fileName);
}
