import 'dart:async';
import 'dart:io' if (dart.library.html) 'package:recipe_app/shared/stubs/io_stub.dart';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
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
  final List<XFile> _images = [];
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
  final Map<String, Future<Uint8List>> _thumbFutures = {};

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
    _cancelToken?.cancel();
    _nameController.dispose();
    _resultController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
      try {
        if (source == ImageSource.camera) {
          final status = await Permission.camera.request();
          if (status.isDenied || status.isPermanentlyDenied) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(status.isPermanentlyDenied
                    ? 'Camera permission denied — enable in app settings'
                    : 'Camera permission required'),
                action: status.isPermanentlyDenied
                    ? SnackBarAction(label: 'Settings', onPressed: () => openAppSettings())
                    : null,
              ),
            );
            return;
          }
        } else {
          final photoStatus = await Permission.photos.request();
          if (photoStatus.isPermanentlyDenied) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Photo permission denied — enable in app settings'),
                action: SnackBarAction(label: 'Settings', onPressed: () => openAppSettings()),
              ),
            );
          }
        }
      } catch (_) {}
    }
    final picker = ImagePicker();
    try {
      if (source == ImageSource.gallery) {
        final picked = await picker.pickMultiImage(maxWidth: 2048);
        if (picked.isNotEmpty) {
          setState(() {
            _images.addAll(picked);
            _textContent = null;
            _resetSteps();
          });
        }
      } else {
        final picked = await picker.pickImage(source: source, maxWidth: 2048);
        if (picked != null) {
          setState(() {
            _images.add(picked);
            _textContent = null;
            _resetSteps();
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not pick image: $e')));
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final pf = result.files.single;
    final ext = pf.extension?.toLowerCase() ?? '';

    final imageExtensions = ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'];
    if (imageExtensions.contains(ext)) {
      final xfile = pf.path != null && !kIsWeb ? XFile(pf.path!) : (pf.bytes != null ? XFile.fromData(pf.bytes!, name: pf.name, mimeType: 'image/$ext') : null);
      if (xfile != null) {
        setState(() {
          _images.add(xfile);
          _textContent = null;
          _resetSteps();
        });
      }
    } else {
      try {
        String? content;
        if (pf.bytes != null) {
          content = String.fromCharCodes(pf.bytes!);
        } else if (pf.path != null) {
          content = await File(pf.path!).readAsString();
        }
        if (content != null) {
          setState(() {
            _textContent = content;
            _images.clear();
            _resetSteps();
          });
        }
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
      List<Uint8List>? imageBytes;
      List<String>? imageNames;
      if (_images.isNotEmpty) {
        imageBytes = [];
        imageNames = [];
        for (final xf in _images) {
          try {
            final bytes = await xf.readAsBytes();
            imageBytes.add(bytes);
            imageNames.add(xf.name.isNotEmpty ? xf.name : 'image.jpg');
          } catch (_) {}
        }
      }
      final result = await repo.transcodeStreaming(
        modelId: modelId,
        systemPrompt: prompt,
        imagePaths: (imageBytes != null && imageBytes.isNotEmpty) ? null : (kIsWeb ? null : _images.map((f) => f.path).toList()),
        imageBytesList: imageBytes,
        imageNames: imageNames,
        textContent: _textContent,
        cancelToken: _cancelToken,
        onEvent: (event, data) {
          if (!mounted) return;
          switch (event) {
            case 'model_load.start':
              _setStep(1, _StepState.active);
            case 'model_load.progress':
              final p = (data['progress'] as num?)?.toDouble();
              if (p != null) setState(() => _modelLoadProgress = p);
            case 'model_load.end':
              _setStep(1, _StepState.done);
              _setStep(2, _StepState.active);
              setState(() => _modelLoadProgress = null);
            case 'prompt_processing.start':
              _setStep(2, _StepState.active);
            case 'message.delta':
              final inc = data['token_count'] as int? ?? (data['content'] as String?)?.length ?? 1;
              setState(() => _tokenCount = (_tokenCount ?? 0) + inc);
            case 'error':
              streamingError = (data['message'] as String?) ??
                  (data['error'] as String?) ??
                  data.toString();
              _setStep(2, _StepState.done);
            case 'chat.end':
            case 'message.end':
              _setStep(2, _StepState.done);
              setState(() => _modelLoadProgress = null);
          }
        },
      );
      _setStep(2, _StepState.done);
      setState(() => _modelLoadProgress = null);

      if (!_cancelling) {
        final stripped = result != null ? _sanitizeModelOutput(result) : null;
        final isEmpty = stripped == null || stripped.trim().isEmpty;
        setState(() {
          _result = isEmpty ? null : stripped;
          if (_result != null) _resultController.text = _result!;
        });
        if (isEmpty && mounted) {
          final hint = settings.lmStudioUrl.contains('localhost') && !kIsWeb
              ? ' On mobile use http://<PC-LAN-IP>:1234, not localhost. Also check LM Studio exposes /v1/chat/completions or /api/v1/chat.'
              : ' Check model is vision-capable and URL is correct.';
          final msg = streamingError != null
              ? '$streamingError$hint'
              : 'Empty response — no content returned.$hint (URL: ${settings.lmStudioUrl})';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Formatting failed: $msg'),
              duration: const Duration(seconds: 6),
            ),
          );
        }
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

  void _showFullScreenImageForXFile(BuildContext context, XFile file) {
    final cs = Theme.of(context).colorScheme;
    final key = file.path.isNotEmpty ? file.path : file.name;
    final fut = _thumbFutures[key] ?? file.readAsBytes();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: cs.surface,
          appBar: AppBar(backgroundColor: cs.surface),
          body: Center(
            child: InteractiveViewer(
              panEnabled: true,
              minScale: 0.5,
              maxScale: 4.0,
              child: FutureBuilder<Uint8List>(
                future: fut,
                builder: (c, snap) {
                  if (snap.hasData) return Image.memory(snap.data!, fit: BoxFit.contain);
                  return const CircularProgressIndicator();
                },
              ),
            ),
          ),
        ),
      ),
    );
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
              child: kIsWeb
                  ? const Icon(Icons.broken_image)
                  : Image.file(File(imagePath) as dynamic, fit: BoxFit.contain),
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
    String _sanitize(String t) {
      var s = t.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '-');
      if (!s.toLowerCase().endsWith('.md')) s = '$s.md';
      return s;
    }
    final filename = _sanitize(name);
    final repo = ref.read(recipeRepositoryProvider).valueOrNull;

    if (repo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Set a recipe directory in Settings first')),
      );
      return;
    }

    final imagePaths = <String>[];
    final slug = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
    if (_attachImages && _images.isNotEmpty && !kIsWeb) {
      try {
        final rp = repo.rootPath;
        final isHttp = rp != null && (rp.startsWith('http://') || rp.startsWith('https://'));
        if (rp != null && !isHttp) {
          final folderDir = Directory(p.join(rp, folder));
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
                final bytes = await sourceFile.readAsBytes();
                await File(destPath).writeAsBytes(bytes);
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

    String finalContent = _sanitizeModelOutput(_result!);
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
        final key = _images[i].path.isNotEmpty ? _images[i].path : _images[i].name;
        final fut = _thumbFutures.putIfAbsent(key, () => _images[i].readAsBytes());
        return Stack(
          children: [
            GestureDetector(
              onTap: () => _showFullScreenImageForXFile(context, _images[i]),
              child: Container(
                width: 100, height: 100,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: FutureBuilder<Uint8List>(
                    future: fut,
                    builder: (ctx, snap) {
                      if (!snap.hasData) return const SizedBox();
                      return Image.memory(snap.data!, fit: BoxFit.cover);
                    },
                  ),
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
    final effectiveValue = _selectedFolder != null && (folders.contains(_selectedFolder) || _selectedFolder == '__new__') ? _selectedFolder : null;
    final showSelectedAsExtra = _selectedFolder != null && !folders.contains(_selectedFolder) && _selectedFolder != '__new__' && _selectedFolder!.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey(effectiveValue ?? '__null__'),
          initialValue: effectiveValue,
          items: [
            ...folders.map((f) => DropdownMenuItem(
                  value: f,
                  child: Text(f),
                )),
            if (showSelectedAsExtra)
              DropdownMenuItem(
                value: _selectedFolder,
                child: Text(_selectedFolder!),
              ),
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
    final bottomPad = MediaQuery.of(context).viewPadding.bottom + MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Auto Format'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(bottom: bottomPad + AppSpacing.md),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
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
                                  width: double.infinity,
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
                    if (!hasSource && _result == null && !_loading)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.md),
                        child: Text(
                          'Tip: on mobile use your PC\'s LAN IP (e.g. http://192.168.1.10:1234) in Settings → LM Studio URL, not localhost.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),
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

String _sanitizeModelOutput(String text) {
  var t = text;
  t = t.replaceAll(RegExp(r'<think>.*?</think>', caseSensitive: false, dotAll: true), '');
  t = t.replaceAll(RegExp(r'<thinking>.*?</thinking>', caseSensitive: false, dotAll: true), '');
  t = t.replaceAll(RegExp(r'<reasoning>.*?</reasoning>', caseSensitive: false, dotAll: true), '');
  t = t.replaceAll(RegExp(r'<thought>.*?</thought>', caseSensitive: false, dotAll: true), '');
  t = t.replaceAll(RegExp(r'<analysis>.*?</analysis>', caseSensitive: false, dotAll: true), '');
  t = t.replaceAll(RegExp(r'<\|channel\|>.*?<\|message\|>', caseSensitive: false, dotAll: true), '');
  t = t.replaceAll(RegExp(r'^\s*(reasoning|thought|analysis|chain-of-thought)\s*:.*$', caseSensitive: false, multiLine: true), '');
  t = t.replaceAll('```', '');
  t = t.replaceAll(RegExp(r'^\s*yaml\s*$', multiLine: true, caseSensitive: false), '');
  t = t.trim();
  t = _stripCodeFences(t);
  t = t.trim();

  final fmRegex = RegExp(r'^\s*---\s*\n([\s\S]*?)\n\s*---\s*\n', multiLine: true);
  final fms = fmRegex.allMatches(t).toList();
  String frontmatter = '';
  int fmEnd = 0;
  if (fms.isNotEmpty) {
    for (var i = 0; i < fms.length; i++) {
      final block = fms[i].group(0)!;
      if (block.contains('title:')) {
        frontmatter = block.trim();
        fmEnd = fms[i].end;
        break;
      }
    }
    if (frontmatter.isEmpty) {
      frontmatter = fms.first.group(0)!.trim();
      fmEnd = fms.first.end;
    }
  } else {
    final idx = t.indexOf('---');
    if (idx != -1) {
      final second = t.indexOf('---', idx + 3);
      if (second != -1) {
        final endNl = t.indexOf('\n', second + 3);
        final end = endNl == -1 ? t.length : endNl + 1;
        frontmatter = t.substring(idx, end).trim();
        fmEnd = end;
      }
    }
  }
  if (frontmatter.isEmpty) {
    final m = RegExp(r'---\s*\n').firstMatch(t);
    if (m != null) {
      t = t.substring(m.start).trim();
      return t;
    }
    return t.trim();
  }

  frontmatter = frontmatter.split('\n').map((e) => e.trim()).join('\n').trim();

  var remainder = t.substring(fmEnd).trim();

  final ingIdx = remainder.toLowerCase().indexOf('## ingredients');
  if (ingIdx != -1) {
    final firstMatch = RegExp(r'##\s*ingredients', caseSensitive: false).firstMatch(remainder);
    if (firstMatch != null) {
      remainder = remainder.substring(firstMatch.start);
    }
  }

  final lines = remainder.split('\n');
  final kept = <String>[];
  final allowedHeader = RegExp(r'^##\s+(Ingredients|Instructions|Nutrition|Notes)\s*$', caseSensitive: false);
  final subHeader = RegExp(r'^###\s+.+');
  final ingredientCheckbox = RegExp(r'^- \[[ xX]\]\s+.+');
  final ingredientPlainBullet = RegExp(r'^- +.+');
  final numbered = RegExp(r'^\d+[\.\)]\s+.+');
  final tableRow = RegExp(r'^\|.*\|\s*$');
  final tableSep = RegExp(r'^\|[\s\-:|]+\|\s*$');
  String currentSection = '';
  String currentHeaderCanonical = '';
  final seenHeaders = <String>{};
  bool skipDuplicateSection = false;

  String canonicalHeader(String h) {
    final lower = h.toLowerCase().trim();
    if (lower.contains('ingredient')) return 'Ingredients';
    if (lower.contains('instruction') || lower.contains('direction') || lower.contains('step')) return 'Instructions';
    if (lower.contains('nutrition')) return 'Nutrition';
    if (lower.contains('note')) return 'Notes';
    return h;
  }

  for (final raw in lines) {
    final line = raw.trimRight();
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      if (!skipDuplicateSection) kept.add('');
      continue;
    }
    final headerMatch = RegExp(r'^##\s+(.+)\s*$').firstMatch(trimmed);
    if (headerMatch != null) {
      final rawHeader = headerMatch.group(1)!.trim();
      final canonical = canonicalHeader(rawHeader);
      final isAllowed = allowedHeader.hasMatch('## $canonical');
      if (isAllowed) {
        if (seenHeaders.contains(canonical)) {
          skipDuplicateSection = true;
          continue;
        }
        seenHeaders.add(canonical);
        skipDuplicateSection = false;
        currentSection = canonical;
        currentHeaderCanonical = canonical;
        kept.add('## $canonical');
        continue;
      } else {
        skipDuplicateSection = true;
        continue;
      }
    }
    if (skipDuplicateSection) continue;
    if (subHeader.hasMatch(trimmed)) {
      if (currentHeaderCanonical == 'Ingredients') kept.add(trimmed);
      continue;
    }
    if (ingredientCheckbox.hasMatch(trimmed)) {
      if (currentHeaderCanonical == 'Ingredients' || currentHeaderCanonical.isEmpty) {
        kept.add(trimmed);
        if (currentHeaderCanonical.isEmpty) currentHeaderCanonical = 'Ingredients';
        continue;
      }
    }
    if (ingredientPlainBullet.hasMatch(trimmed) && currentHeaderCanonical == 'Ingredients') {
      kept.add(trimmed);
      continue;
    }
    if (numbered.hasMatch(trimmed)) {
      if (currentHeaderCanonical == 'Instructions' || currentHeaderCanonical == 'Ingredients') {
        if (currentHeaderCanonical == 'Ingredients' && !trimmed.startsWith('-')) {
          currentHeaderCanonical = 'Instructions';
          currentSection = 'Instructions';
        }
        kept.add(trimmed);
        continue;
      }
    }
    if (tableRow.hasMatch(trimmed) || tableSep.hasMatch(trimmed)) {
      if (currentHeaderCanonical == 'Nutrition') kept.add(trimmed);
      continue;
    }
    if (ingredientPlainBullet.hasMatch(trimmed)) {
      if (currentHeaderCanonical == 'Notes' || currentHeaderCanonical == 'Nutrition') {
        kept.add(trimmed);
        continue;
      }
      if (currentHeaderCanonical == 'Instructions') {
        kept.add(trimmed);
        continue;
      }
      continue;
    }
    final isHallucinated = trimmed.startsWith('**') ||
        trimmed.startsWith('Let\'s') ||
        trimmed.startsWith('From input') ||
        trimmed.startsWith('Format as') ||
        trimmed.startsWith('Convert ') ||
        trimmed.startsWith('Wait,') ||
        trimmed.startsWith('Actually,') ||
        trimmed.startsWith('I will') ||
        trimmed.startsWith('Check ') ||
        trimmed.startsWith('Re-format') ||
        RegExp(r'^\d+\.\s+\*\*').hasMatch(trimmed) ||
        trimmed.contains('Identify Ingredients') ||
        trimmed.contains('Identify Instructions') ||
        trimmed.contains('Check Constraints');
    if (isHallucinated) continue;
    if (currentHeaderCanonical.isNotEmpty) {
      kept.add(trimmed);
    }
  }

  while (kept.isNotEmpty && kept.first.trim().isEmpty) kept.removeAt(0);
  while (kept.isNotEmpty && kept.last.trim().isEmpty) kept.removeLast();

  final body = kept.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  if (body.isEmpty) return frontmatter;
  return '$frontmatter\n\n$body'.trim();
}
