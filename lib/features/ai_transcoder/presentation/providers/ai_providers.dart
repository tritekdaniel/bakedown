import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/lm_studio_repository.dart';
import '../../domain/models/lm_studio_model.dart';
import 'package:recipe_app/features/settings/presentation/providers/settings_providers.dart';

final lmStudioRepositoryProvider = Provider<LmStudioRepository>((ref) {
  final url = ref.watch(settingsProvider.select((s) => s.lmStudioUrl));
  return LmStudioRepository(url);
});

final availableModelsProvider = FutureProvider<List<LmStudioModel>>((ref) {
  final repo = ref.watch(lmStudioRepositoryProvider);
  return repo.listModels();
});

final transcodeStateProvider = StateProvider<AsyncValue<String?>>((ref) {
  return const AsyncData(null);
});
