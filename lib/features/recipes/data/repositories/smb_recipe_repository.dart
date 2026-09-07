import '../models/recipe_model.dart';
import 'recipe_repository.dart';

// Stub kept for backward compat — OS file picker + LocalRecipeRepository now handles
// network shares via the OS (UNC / mounted shares). This class is no longer used
// on web/desktop; kept only so old imports don't break.
class SmbRecipeRepository implements RecipeRepository {
  final String host;
  final String domain;
  final String username;
  final String password;
  final String share;
  final String subPath;

  SmbRecipeRepository({
    required this.host,
    this.domain = '',
    required this.username,
    required this.password,
    required this.share,
    this.subPath = '',
  });

  Future<void> connect({bool debugPrint = false}) async {}

  @override
  String? get rootPath => null;

  @override
  Future<List<String>> listFolders() async => [];

  @override
  Future<List<String>> listSubfolders(String folder) async => [];

  @override
  Future<List<RecipeModel>> listRecipes(String folder) async => [];

  @override
  Future<String?> readFile(String folder, String filename) async => null;

  @override
  Future<bool> writeFile(String folder, String filename, String content) async => false;

  @override
  Future<bool> deleteFile(String folder, String filename) async => false;

  @override
  Future<bool> deleteFolder(String folderName) async => false;

  @override
  Future<bool> createFolder(String folderName) async => false;

  @override
  Future<String> imagePathFor(String folder, String fileName) async => '';

  Future<void> dispose() async {}

  Future<String> diagnostics() async => 'SMB stub — use OS picker';

  Future<List<String>> listShares() async => [];
}
