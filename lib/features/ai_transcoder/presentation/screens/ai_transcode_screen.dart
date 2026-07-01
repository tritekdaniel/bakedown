import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../settings/presentation/providers/settings_providers.dart';
import '../../../recipes/presentation/providers/recipe_providers.dart';
import '../../data/repositories/lm_studio_repository.dart';

class AITranscodeScreen extends ConsumerStatefulWidget {
  final String? initialText;

  const AITranscodeScreen({super.key, this.initialText});

  @override
  ConsumerState<AITranscodeScreen> createState() => _AITranscodeScreenState();
}

enum _StepState { waiting, active, done, skipped }

class _AITranscodeScreenState extends ConsumerState<AITranscodeScreen> {
  final List<File> _images = [];
  String? _textContent;
  String? _result;
  bool _loading = false;
  bool _cancelling = false;
  CancelToken? _cancelToken;
  double? _modelLoadProgress;
  int? _tokenCount;
  DateTime? _generationStart;
  bool _attachImages = true;
  final _stepLabels = const ['Check model', 'Load model', 'Generate recipe'];
  final _stepStates = List<_StepState>.filled(3, _StepState.waiting);
  final _nameController = TextEditingController();
  String? _selectedFolder;
  late final TextEditingController _resultController;

  @override
  void initState() {
    super.initState();
    _resultController = TextEditingController();
    _resultController.addListener(() => _result = _resultController.text);
    final initial = widget.initialText;
    if (initial != null && initial.isNotEmpty) {
      _textContent = initial;
      _resultController.text = initial;
    }
  }

  void _resetSteps() {
    for (var i = 0; i < _stepStates.length; i++) {
      _stepStates[i] = _StepState.waiting;
    }
    _modelLoadProgress = null;
    _tokenCount = null;
    _generationStart = null;
  }

  void _clearImages() {
    setState(() {
      _images.clear();
      _textContent = null;
      _result = null;
      _resetSteps();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _resultController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    if (source == ImageSource.gallery) {
      final picked = await picker.pickMultiImage(maxWidth: 2048);
      if (picked.isNotEmpty) {
        setState(() {
          _images.addAll(picked.map((p) => File(p.path)));
          _textContent = null;
          _resetSteps();
        });
      }
    } else {
      final picked = await picker.pickImage(source: source, maxWidth: 2048);
      if (picked != null) {
        setState(() {
          _images.add(File(picked.path));
          _textContent = null;
          _resetSteps();
        });
      }
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.isEmpty) return;
    final file = File(result.files.single.path!);
    final ext = result.files.single.extension?.toLowerCase() ?? '';

    final imageExtensions = ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'];
    if (imageExtensions.contains(ext)) {
      setState(() {
        _images.add(file);
        _textContent = null;
        _resetSteps();
      });
    } else {
      try {
        final content = await file.readAsString();
        setState(() {
          _textContent = content;
          _images.clear();
          _resetSteps();
        });
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not read file as text')),
          );
        }
      }
    }
  }

  Future<void> _transcode() async {
    if (_images.isEmpty && _textContent == null) return;

    final settings = ref.read(settingsProvider);
    final modelId = settings.selectedModel ?? '';

    if (modelId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select a model in Settings first')),
        );
      }
      return;
    }

    setState(() {
      _loading = true;
      _cancelling = false;
      _resetSteps();
    });

    try {
      final repo = LmStudioRepository(settings.lmStudioUrl);
      final bundle = DefaultAssetBundle.of(context);

      _setStep(0, _StepState.active);
      final loaded = await repo.getLoadedModelIds();
      final selectedLoaded = loaded.any((id) => id == modelId);
      _setStep(0, _StepState.done);

      _generationStart = DateTime.now();
      _cancelToken = CancelToken();
      if (selectedLoaded) {
        _setStep(1, _StepState.skipped);
        _setStep(2, _StepState.active);
      } else {
        _setStep(1, _StepState.active);
      }
      final prompt =
          await bundle.loadString('assets/prompts/recipe-system-prompt.md');
      String? streamingError;
      final imagePaths = _images.map((f) => f.path).toList();
      final result = await repo.transcodeStreaming(
        modelId: modelId,
        systemPrompt: prompt,
        imagePaths: imagePaths.isEmpty ? null : imagePaths,
        textContent: _textContent,
        cancelToken: _cancelToken,
        onEvent: (event, data) {
          if (!mounted) return;
          switch (event) {
            case 'model_load.start':
              _setStep(1, _StepState.active);
            case 'model_load.progress':
              setState(() => _modelLoadProgress = (data['progress'] as num?)?.toDouble());
            case 'model_load.end':
              _setStep(1, _StepState.done);
              _setStep(2, _StepState.active);
              setState(() => _modelLoadProgress = null);
            case 'prompt_processing.start':
              _setStep(2, _StepState.active);
            case 'message.delta':
              setState(() => _tokenCount = (_tokenCount ?? 0) + (data['token_count'] as int? ?? 1));
            case 'error':
              streamingError = data['message'] as String? ?? 'Unknown error';
              _setStep(2, _StepState.done);
            case 'chat.end':
            case 'message.end':
              _setStep(2, _StepState.done);
          }
        },
      );
      _setStep(2, _StepState.done);

      if (!_cancelling) {
        setState(() {
          _result = result != null ? _stripCodeFences(result) : null;
          if (_result != null) _resultController.text = _result!;
        });
      }

      if (result == null && mounted && !_cancelling) {
        final msg = streamingError ?? 'Check LM Studio connection or URL: ${settings.lmStudioUrl}';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Formatting failed: $msg')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _cancelling = false;
        });
      }
    }
  }

  void _cancelTranscode() {
    setState(() => _cancelling = true);
    _cancelToken?.cancel();
  }

  void _setStep(int index, _StepState state) {
    if (!mounted) return;
    setState(() => _stepStates[index] = state);
  }

  void _showFullScreenImage(BuildContext context, String imagePath) {
    final cs = Theme.of(context).colorScheme;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: cs.surface,
          appBar: AppBar(
            backgroundColor: cs.surface,
          ),
          body: Center(
            child: InteractiveViewer(
              panEnabled: true,
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.file(File(imagePath), fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _saveResult() async {
    if (_result == null) return;
    final folder = _selectedFolder;
    final name = _nameController.text.trim();
    if (folder == null || folder.isEmpty || name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a folder and enter a recipe name')),
      );
      return;
    }
    final filename = '$name.md';
    final repo = ref.read(recipeRepositoryProvider).valueOrNull;

    if (repo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Set a recipe directory in Settings first')),
      );
      return;
    }

    final imagePaths = <String>[];
    final slug = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
    if (_attachImages && _images.isNotEmpty) {
      try {
        if (repo.rootPath != null) {
          final folderDir = Directory(p.join(repo.rootPath!, folder));
          if (!folderDir.existsSync()) {
            folderDir.createSync(recursive: true);
          }
          for (var i = 0; i < _images.length; i++) {
            final sourceFile = _images[i];
            final destPath = p.join(folderDir.path, '$slug-${i + 1}.jpg');
            try {
              if (sourceFile.path.startsWith('content://')) {
                await XFile(sourceFile.path).saveTo(destPath);
              } else {
                await sourceFile.copy(destPath);
              }
              imagePaths.add('$slug-${i + 1}.jpg');
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Failed to copy image $i: $e')),
              );
            }
          }
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to prepare image directory: $e')),
        );
      }
    }

    String finalContent = _result!;
    if (imagePaths.isNotEmpty) {
      final lines = finalContent.split('\n');
      if (lines.isNotEmpty && lines.first.trim() == '---') {
        int closingIdx = -1;
        for (var i = 1; i < lines.length; i++) {
          if (lines[i].trim() == '---') {
            closingIdx = i;
            break;
          }
        }
        if (closingIdx > 0) {
          final imagesLine = 'images: [${imagePaths.join(', ')}]';
          lines.insert(closingIdx, imagesLine);
          finalContent = lines.join('\n');
        }
      }
    }

    final ok = await repo.writeFile(folder, filename, finalContent);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Save failed — check folder permissions')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Recipe saved!${imagePaths.isNotEmpty ? ' (${imagePaths.length} image(s) attached)' : ''}'))
    );
    setState(() {
      _images.clear();
      _textContent = null;
      _nameController.clear();
      _selectedFolder = null;
      _resultController.clear();
      _result = null;
      _resetSteps();
    });
  }

  void _showNewFolderDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Folder'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Folder name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                final repo = ref.read(recipeRepositoryProvider).valueOrNull;
                final ok = repo != null ? await repo.createFolder(controller.text) : false;
                ref.invalidate(foldersProvider);
                _selectedFolder = controller.text;
                if (ctx.mounted) Navigator.pop(ctx);
                if (!ok && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Create failed — check folder permissions')),
                  );
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  // ── Build helpers ──

  Widget _sectionHeader(String title, IconData icon) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: AppSpacing.xs),
        Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _sourcePicker() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
          child: Icon(Icons.restaurant_menu, size: 40, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
        ),
        Text('Provide a recipe source',
            style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: AppSpacing.xxs),
        Text('Take a photo, pick from gallery, or upload a file',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pickImage(ImageSource.camera),
                icon: const Icon(Icons.camera_alt),
                label: const Text('Camera'),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pickImage(ImageSource.gallery),
                icon: const Icon(Icons.photo_library),
                label: const Text('Gallery'),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        OutlinedButton.icon(
          onPressed: _pickFile,
          icon: const Icon(Icons.upload_file),
          label: const Text('From File'),
        ),
      ],
    );
  }

  Widget _imageGrid() {
    return Wrap(
      spacing: AppSpacing.xxs,
      runSpacing: AppSpacing.xxs,
      children: List.generate(_images.length, (i) {
        return Stack(
          children: [
            GestureDetector(
              onTap: () => _showFullScreenImage(context, _images[i].path),
              child: Container(
                width: 100, height: 100,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: Image.file(_images[i], fit: BoxFit.cover),
                ),
              ),
            ),
            Positioned(
              top: 0, right: 0,
              child: GestureDetector(
                onTap: () => setState(() => _images.removeAt(i)),
                child: Container(
                  width: 24, height: 24,
                  decoration:                   BoxDecoration(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, size: 16),
                ),
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _textPreview() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Chip(
          avatar: Icon(Icons.description, size: 16, color: theme.colorScheme.onTertiaryContainer),
          label: Text('Text file loaded', style: TextStyle(color: theme.colorScheme.onTertiaryContainer)),
          backgroundColor: theme.colorScheme.tertiaryContainer,
          side: BorderSide.none,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        const SizedBox(height: AppSpacing.xs),
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          height: 200,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              _textContent!,
              style: theme.textTheme.labelSmall?.copyWith(fontFamily: 'monospace'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _sourceContent() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_images.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_images.length} image${_images.length == 1 ? '' : 's'} selected  ·  tap to expand',
                style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          _imageGrid(),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Icon(Icons.save, size: 16, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: AppSpacing.xxs),
              Text('Attach images when saving',
                  style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const Spacer(),
              Switch(
                value: _attachImages,
                onChanged: (v) => setState(() => _attachImages = v),
              ),
            ],
          ),
        ],
        if (_textContent != null) _textPreview(),
        const SizedBox(height: AppSpacing.xs),
        TextButton.icon(
          onPressed: _clearImages,
          icon: const Icon(Icons.refresh),
          label: const Text('Choose different source'),
        ),
      ],
    );
  }

  Widget _resultEditor() {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(maxHeight: 400),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: TextField(
          controller: _resultController,
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
          decoration: const InputDecoration(
            border: InputBorder.none,
            contentPadding: EdgeInsets.all(AppSpacing.md),
          ),
        ),
      ),
    );
  }

  Widget _saveForm() {
    final folders = ref.watch(foldersProvider).valueOrNull ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey(_selectedFolder),
          initialValue: _selectedFolder,
          items: [
            ...folders.map((f) => DropdownMenuItem(
                  value: f,
                  child: Text(f),
                )),
            const DropdownMenuItem(
              value: '__new__',
              child: Text('New folder...'),
            ),
          ],
          onChanged: (v) {
            if (v == '__new__') {
              _showNewFolderDialog();
            } else {
              setState(() => _selectedFolder = v);
            }
          },
          decoration: const InputDecoration(
            labelText: 'Folder',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: 'Recipe name',
            hintText: 'e.g. Spaghetti Carbonara',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        FilledButton.icon(
          onPressed: _saveResult,
          icon: const Icon(Icons.save),
          label: const Text('Save Recipe'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasSource = _images.isNotEmpty || _textContent != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Auto Format'),
      ),
      body: SingleChildScrollView(
        child: Center(
          child: SizedBox(
            width: 960,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _sectionHeader('Recipe Source', Icons.source_outlined),
                          const SizedBox(height: AppSpacing.sm),
                          if (!hasSource) _sourcePicker(),
                          if (hasSource) ...[
                            _sourceContent(),
                            const SizedBox(height: AppSpacing.sm),
                            if (_loading)
                              _ProcessingStatusCard(
                                stepLabels: _stepLabels,
                                stepStates: _stepStates,
                                onCancel: _cancelTranscode,
                                modelLoadProgress: _modelLoadProgress,
                                tokenCount: _tokenCount,
                                generationStart: _generationStart,
                              )
                            else
                              SizedBox(
                                height: 48,
                                child: FilledButton.icon(
                                  onPressed: _transcode,
                                  icon: const Icon(Icons.auto_awesome),
                                  label: const Text('Format Recipe'),
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (_result != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _sectionHeader('Preview & Save', Icons.article_outlined),
                            const SizedBox(height: AppSpacing.sm),
                            _resultEditor(),
                            const SizedBox(height: AppSpacing.sm),
                            _saveForm(),
                          ],
                        ),
                      ),
                    ),
                  ],
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}

// ────────────────────────────────────────────
// Processing status card with elapsed timer
// ────────────────────────────────────────────

class _ProcessingStatusCard extends StatefulWidget {
  final List<String> stepLabels;
  final List<_StepState> stepStates;
  final VoidCallback? onCancel;
  final double? modelLoadProgress;
  final int? tokenCount;
  final DateTime? generationStart;

  const _ProcessingStatusCard({
    required this.stepLabels,
    required this.stepStates,
    this.onCancel,
    this.modelLoadProgress,
    this.tokenCount,
    this.generationStart,
  });

  @override
  State<_ProcessingStatusCard> createState() => _ProcessingStatusCardState();
}

class _ProcessingStatusCardState extends State<_ProcessingStatusCard> {
  Timer? _timer;
  int _elapsed = 0;

  @override
  void initState() {
    super.initState();
    _maybeStartTimer();
  }

  @override
  void didUpdateWidget(_ProcessingStatusCard old) {
    super.didUpdateWidget(old);
    if (old.generationStart == null && widget.generationStart != null) {
      _elapsed = 0;
      _maybeStartTimer();
    }
    if (old.generationStart != null && widget.generationStart == null) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _maybeStartTimer() {
    if (widget.generationStart != null && _timer == null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() {
            _elapsed = DateTime.now().difference(widget.generationStart!).inSeconds;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatElapsed(int sec) {
    final min = sec ~/ 60;
    final s = sec % 60;
    return '$min:${s.toString().padLeft(2, '0')} elapsed';
  }

  double? _tokenRate() {
    if (widget.tokenCount == null || widget.tokenCount! <= 0 || _elapsed <= 0) return null;
    return widget.tokenCount! / _elapsed;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stepStates = widget.stepStates;
    final generating = stepStates.length > 2 && stepStates[2] == _StepState.active;
    final rate = _tokenRate();

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 500;
        final cards = [
          Expanded(
            child: Card(
              color: theme.colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                side: BorderSide(color: theme.colorScheme.outlineVariant, width: 0.5),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.sync, size: 18, color: theme.colorScheme.primary),
                            const SizedBox(width: AppSpacing.xs),
                            Text('Processing', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                          ],
                        ),
                        if (widget.onCancel != null)
                          TextButton.icon(
                            onPressed: widget.onCancel,
                            icon: const Icon(Icons.close, size: 18),
                            label: const Text('Cancel'),
                            style: TextButton.styleFrom(
                              foregroundColor: theme.colorScheme.error,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    for (var i = 0; i < widget.stepLabels.length; i++) ...[
                      if (i > 0) const SizedBox(height: AppSpacing.xs),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        decoration: BoxDecoration(
                          color: stepStates[i] == _StepState.active
                              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
                        child: _buildStepRow(i, theme),
                      ),
                    ],
                    if (widget.modelLoadProgress != null && widget.modelLoadProgress! > 0 && widget.modelLoadProgress! < 1) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          SizedBox(
                            width: 100,
                            child: LinearProgressIndicator(
                              value: widget.modelLoadProgress,
                              backgroundColor: theme.colorScheme.surfaceContainerHighest,
                              minHeight: 4,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            'Loading model: ${(widget.modelLoadProgress! * 100).toInt()}%',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          SizedBox(width: wide ? AppSpacing.md : 0, height: wide ? 0 : AppSpacing.md),
          Expanded(
            child: Card(
              color: theme.colorScheme.surfaceContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                side: BorderSide(color: theme.colorScheme.outlineVariant, width: 0.5),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Stats', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: AppSpacing.sm),
                    if (generating && widget.tokenCount != null && widget.tokenCount! > 0) ...[
                      Row(
                        children: [
                          Icon(Icons.tag, size: 16, color: theme.colorScheme.primary),
                          const SizedBox(width: AppSpacing.xxs),
                          Text(
                            '${widget.tokenCount} tokens',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (rate != null) ...[
                            const SizedBox(width: AppSpacing.xs),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(AppRadius.xs),
                              ),
                              child: Text(
                                '${rate.toStringAsFixed(1)} tok/s',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                    if (generating && _elapsed > 0) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        children: [
                          Icon(Icons.timer_outlined, size: 16, color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: AppSpacing.xxs),
                          Text(
                            _formatElapsed(_elapsed),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (generating && (widget.tokenCount == null || widget.tokenCount! == 0)) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            'Thinking...',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ];

        if (wide) {
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: cards);
        }
        return Column(children: cards);
      },
    );
  }

  Widget _buildStepRow(int index, ThemeData theme) {
    final state = widget.stepStates[index];
    final label = widget.stepLabels[index];
    final active = state == _StepState.active;

    IconData icon;
    Color? iconColor;
    switch (state) {
      case _StepState.waiting:
        icon = Icons.circle_outlined;
        iconColor = theme.colorScheme.outline;
      case _StepState.active:
        icon = Icons.autorenew;
        iconColor = theme.colorScheme.primary;
      case _StepState.done:
        icon = Icons.check_circle;
        iconColor = theme.colorScheme.primary;
      case _StepState.skipped:
        icon = Icons.remove_circle_outline;
        iconColor = theme.colorScheme.outline;
    }

    return Row(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: active
              ? SizedBox(
                  key: const ValueKey('spinner'),
                  width: 22, height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: iconColor,
                  ),
                )
              : Icon(icon, key: ValueKey(icon), size: 22, color: iconColor),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: active
                ? theme.colorScheme.onSurface
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: active ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}

String _stripCodeFences(String text) {
  var t = text.trim();
  if (t.startsWith('```')) {
    final idx = t.indexOf('\n');
    if (idx > 0) t = t.substring(idx + 1);
    if (t.endsWith('```')) t = t.substring(0, t.length - 3);
  }
  return t.trim();
}
