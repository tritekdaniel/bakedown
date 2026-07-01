import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/recipe_providers.dart';

class FolderTree extends ConsumerWidget {
  const FolderTree({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = ref.watch(foldersProvider).valueOrNull ?? [];
    final currentFolder = ref.watch(currentFolderProvider);
    final theme = Theme.of(context);

    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text('Folders',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              )),
        ),
        ...folders.map((folder) => ListTile(
              leading: Icon(
                folder == currentFolder
                    ? Icons.folder_open
                    : Icons.folder,
                color: folder == currentFolder
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              title: Text(
                folder,
                style: TextStyle(
                  fontWeight: folder == currentFolder
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
              selected: folder == currentFolder,
              dense: true,
              onTap: () {
                ref.read(currentFolderProvider.notifier).state = folder;
              },
            )),
      ],
    );
  }
}
