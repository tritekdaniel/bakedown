import 'dart:io' if (dart.library.html) 'package:recipe_app/shared/stubs/io_stub.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class FileBrowserDialog extends StatefulWidget {
  final String initialPath;

  const FileBrowserDialog({super.key, this.initialPath = ''});

  @override
  State<FileBrowserDialog> createState() => _FileBrowserDialogState();
}

class _FileBrowserDialogState extends State<FileBrowserDialog> {
  String _currentPath = '';
  List<FileSystemEntity> _entries = [];
  List<String> _roots = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initPath();
  }

  Future<void> _initPath() async {
    if (kIsWeb) {
      setState(() {
        _loading = false;
        _error = 'File browser not available on web';
      });
      return;
    }
    String start = widget.initialPath;
    if (start.isNotEmpty) {
      try {
        final d = Directory(start);
        if (await (d.exists() as Future<bool>)) {
          _currentPath = start;
          await _loadEntries();
          return;
        }
      } catch (_) {}
    }
    try {
      final docs = await getApplicationDocumentsDirectory();
      final parent = p.dirname(docs.path);
      if (await Directory(parent).exists()) {
        _currentPath = parent;
      } else {
        _currentPath = docs.path;
      }
    } catch (_) {
      _currentPath = _defaultRoot();
    }
    await _loadEntries();
  }

  String _defaultRoot() {
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
        return 'C:\\';
      }
    } catch (_) {}
    return '/';
  }

  Future<List<String>> _getRoots() async {
    if (kIsWeb) return [];
    try {
      if (defaultTargetPlatform == TargetPlatform.windows) {
        final candidates = <String>[];
        for (var code = 67; code <= 90; code++) {
          final drive = '${String.fromCharCode(code)}:\\';
          try {
            if (await Directory(drive).exists()) candidates.add(drive);
          } catch (_) {}
        }
        if (candidates.isEmpty) candidates.add('C:\\');
        return candidates;
      }
    } catch (_) {}
    return ['/'];
  }

  Future<void> _loadEntries() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_roots.isEmpty) {
        _roots = await _getRoots();
      }
      if (_currentPath.isEmpty) {
        _currentPath = _roots.first;
      }
      final dir = Directory(_currentPath);
      final exists = await dir.exists();
      if (!exists) {
        setState(() {
          _error = 'Folder does not exist';
          _entries = [];
          _loading = false;
        });
        return;
      }
      final list = await dir.list().toList();
      final dirs = <FileSystemEntity>[];
      for (final e in list) {
        try {
          if (e is Directory) {
            dirs.add(e);
          }
        } catch (_) {}
      }
      dirs.sort((a, b) => p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase()));
      if (mounted) {
        setState(() {
          _entries = dirs;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _entries = [];
          _loading = false;
        });
      }
    }
  }

  void _navigateTo(String path) {
    setState(() => _currentPath = path);
    _loadEntries();
  }

  void _goUp() {
    final parent = p.dirname(_currentPath);
    if (parent == _currentPath) return;
    _navigateTo(parent);
  }

  void _goToRoot(String root) {
    _navigateTo(root);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canUp = p.dirname(_currentPath) != _currentPath && _currentPath.isNotEmpty;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.folder_open, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Choose Recipe Folder', style: theme.textTheme.titleMedium),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SelectableText(
                            _currentPath.isEmpty ? '(no folder)' : _currentPath,
                            style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                          ),
                        ),
                      ),
                      if (canUp)
                        IconButton(
                          icon: const Icon(Icons.arrow_upward, size: 18),
                          tooltip: 'Go up',
                          onPressed: _goUp,
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ),
                if (_roots.length > 1) ...[
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _roots.map((r) {
                        final selected = _currentPath.toLowerCase().startsWith(r.toLowerCase());
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(r),
                            selected: selected,
                            onSelected: (_) => _goToRoot(r),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 380),
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
                                const SizedBox(height: 12),
                                Text(_error!, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
                                const SizedBox(height: 12),
                                FilledButton.icon(
                                  onPressed: _loadEntries,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _entries.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.folder_off, size: 48, color: theme.colorScheme.outline),
                                    const SizedBox(height: 12),
                                    Text('No subfolders', style: theme.textTheme.bodyMedium),
                                    const SizedBox(height: 4),
                                    Text('This folder has no subfolders', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                                  ],
                                ),
                              ),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              itemCount: _entries.length,
                              separatorBuilder: (_, __) => Divider(height: 1, color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
                              itemBuilder: (context, index) {
                                final e = _entries[index];
                                final name = p.basename(e.path);
                                return ListTile(
                                  leading: Icon(Icons.folder, color: theme.colorScheme.primary),
                                  title: Text(name.isEmpty ? e.path : name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  subtitle: Text(e.path, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                                  trailing: const Icon(Icons.chevron_right, size: 18),
                                  onTap: () => _navigateTo(e.path),
                                );
                              },
                            ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  onPressed: _currentPath.isEmpty ? null : () => Navigator.pop(context, _currentPath),
                  icon: const Icon(Icons.check),
                  label: Text('Use this folder'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          Navigator.pop(context, '__native__');
                        },
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: const Text('Native picker'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('Cancel'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<String?> showFolderBrowser(BuildContext context, {String initialPath = ''}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: MediaQuery.of(ctx).size.height * 0.85,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: FileBrowserDialog(initialPath: initialPath),
        ),
      ),
    ),
  );
}
