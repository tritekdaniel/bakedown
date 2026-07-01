import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:recipe_app/core/constants/app_constants.dart';
import '../../domain/models/lm_studio_model.dart';

const _timeout = Duration(seconds: 365);
const _quickTimeout = Duration(seconds: 5);

typedef SseEventHandler = void Function(String event, Map<String, dynamic> data);

class ConnectionTestResult {
  final bool success;
  final int? statusCode;
  final String? error;
  final int modelCount;
  final String url;
  final Duration elapsed;

  const ConnectionTestResult({
    required this.success,
    this.statusCode,
    this.error,
    this.modelCount = 0,
    required this.url,
    this.elapsed = Duration.zero,
  });
}

Dio _dio({Duration? receiveTimeout}) => Dio(BaseOptions(
  connectTimeout: const Duration(seconds: 15),
  receiveTimeout: receiveTimeout ?? _quickTimeout,
));

class LmStudioRepository {
  final String baseUrl;

  LmStudioRepository(String url) : baseUrl = AppConstants.normalizeUrl(url);

  Future<ConnectionTestResult> testConnection() async {
    final stopwatch = Stopwatch()..start();
    try {
      final response = await _dio().get('$baseUrl/api/v1/models');
      stopwatch.stop();
      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final models = data['models'] as List<dynamic>? ?? [];
        return ConnectionTestResult(
          success: true,
          statusCode: 200,
          modelCount: models.length,
          url: baseUrl,
          elapsed: stopwatch.elapsed,
        );
      }
      return ConnectionTestResult(
        success: false,
        statusCode: response.statusCode,
        url: baseUrl,
        elapsed: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      String detail;
      if (e is DioException) {
        final type = e.type.name;
        final msg = e.message ?? '';
        final origErr = e.error?.toString() ?? '';
        detail = 'DioException[$type]: $msg${origErr.isNotEmpty ? '\n$origErr' : ''}';
        if (kIsWeb) {
          detail += '\n\nWeb browsers block cross-origin requests (CORS). '
              'Use localhost in URL, or run Windows desktop build for network IPs.';
        }
      } else {
        detail = e.toString();
      }
      return ConnectionTestResult(
        success: false,
        error: detail,
        url: baseUrl,
        elapsed: stopwatch.elapsed,
      );
    }
  }

  Future<List<LmStudioModel>> listModels() async {
    try {
      final response = await _dio().get('$baseUrl/api/v1/models');
      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final models = data['models'] as List<dynamic>? ?? [];
        return models
            .map((m) => LmStudioModel.fromJson(m as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<bool> loadModel(String modelId, {String? preset, int? contextLength, int? gpuOffloadLayers}) async {
    try {
      final body = <String, dynamic>{'model': modelId};
      final config = <String, dynamic>{};
      if (contextLength != null) config['context_length'] = contextLength;
      if (gpuOffloadLayers != null) config['gpu_offload_layers'] = gpuOffloadLayers;
      if (config.isNotEmpty) body['config'] = config;

      final response = await _dio(receiveTimeout: _timeout).post(
        '$baseUrl/api/v1/models/load',
        data: body,
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> unloadModel(String instanceId) async {
    try {
      final response = await _dio().post(
        '$baseUrl/api/v1/models/unload',
        data: {'instance_id': instanceId},
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<List<String>> getLoadedModelIds() async {
    try {
      final response = await _dio().get('$baseUrl/api/v1/models');
      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final models = data['models'] as List<dynamic>? ?? [];
        final loadedIds = <String>[];
        for (final m in models) {
          final instances =
              (m as Map<String, dynamic>)['loaded_instances'] as List<dynamic>?;
          if (instances != null) {
            for (final inst in instances) {
              loadedIds.add(inst['id'] as String);
            }
          }
        }
        return loadedIds;
      }
    } catch (_) {}
    return [];
  }

  Future<void> unloadAll() async {
    final loaded = await getLoadedModelIds();
    for (final id in loaded) {
      await unloadModel(id);
    }
  }

  Future<String?> transcodeStreaming({
    required String modelId,
    required String systemPrompt,
    List<String>? imagePaths,
    String? textContent,
    required SseEventHandler onEvent,
    CancelToken? cancelToken,
  }) async {
    try {
      if (imagePaths == null && textContent == null) return null;

      dynamic input;
      if (imagePaths != null && imagePaths.isNotEmpty) {
        final parts = <Map<String, dynamic>>[
          {'type': 'text', 'content': 'Transcribe these recipe images into the required markdown format.'},
        ];
        for (final path in imagePaths) {
          try {
            final imageBytes = await File(path).readAsBytes();
            final base64Image = base64Encode(imageBytes);
            final ext = path.split('.').last.toLowerCase();
            final mimeType = ext == 'png' ? 'image/png' : 'image/jpeg';
            parts.add({
              'type': 'image',
              'data_url': 'data:$mimeType;base64,$base64Image',
            });
          } catch (_) {}
        }
        input = parts;
      } else {
        input = 'Re-format this recipe into the required markdown format:\n\n$textContent';
      }

      final body = {
        'model': modelId,
        'input': input,
        'system_prompt': systemPrompt,
        'stream': true,
        'temperature': 0.1,
        'max_output_tokens': 2048,
        'store': false,
      };

      final response = await _dio(receiveTimeout: _timeout).post<ResponseBody>(
        '$baseUrl/api/v1/chat',
        data: body,
        options: Options(
          responseType: ResponseType.stream,
          validateStatus: (_) => true,
        ),
        cancelToken: cancelToken,
      );

      if (response.statusCode != 200) {
        String errBody = '';
        try {
          final bytes = <int>[];
          await for (final chunk in response.data!.stream) {
            bytes.addAll(chunk);
          }
          if (bytes.isNotEmpty) errBody = utf8.decode(bytes);
        } catch (_) {}
        final err = errBody.isNotEmpty ? errBody : 'HTTP ${response.statusCode}';
        onEvent('error', {'message': err, 'url': '$baseUrl/api/v1/chat'});
        return null;
      }

      final stream = response.data!.stream;
      final fullContent = StringBuffer();
      var sseBuffer = '';
      var sseEvent = '';
      var sseData = '';

      void processLine(String line) {
        if (line.startsWith('event: ')) {
          sseEvent = line.substring(7).trim();
        } else if (line.startsWith('data: ')) {
          sseData = line.substring(6).trim();
        } else if (line.isEmpty && sseEvent.isNotEmpty && sseData.isNotEmpty) {
          _handleSseEvent(sseEvent, sseData, onEvent, fullContent);
          sseEvent = '';
          sseData = '';
        }
      }

      await for (final chunk in stream) {
        final text = utf8.decode(chunk);
        sseBuffer += text;
        final lines = sseBuffer.split('\n');
        sseBuffer = lines.removeLast();
        for (final line in lines) {
          processLine(line);
        }
      }
      if (sseBuffer.isNotEmpty) processLine(sseBuffer);

      final result = fullContent.toString();
      return result.isNotEmpty ? result : null;
    } catch (e) {
      if (cancelToken?.isCancelled == true) {
        onEvent('cancel', {});
        return null;
      }
      String msg = '$e';
      if (e is DioException && e.response?.data is ResponseBody) {
        try {
          final errBody = e.response!.data as ResponseBody;
          final bytes = <int>[];
          await for (final chunk in errBody.stream) {
            bytes.addAll(chunk);
          }
          if (bytes.isNotEmpty) {
            msg = '${e.response?.statusCode}: ${utf8.decode(bytes)}';
          }
        } catch (_) {}
      }
      onEvent('error', {'message': msg});
      return null;
    }
  }

  void _handleSseEvent(String event, String data, SseEventHandler onEvent, StringBuffer fullContent) {
    try {
      final json = jsonDecode(data) as Map<String, dynamic>;
      
      // Extract additional metadata from events
      final extra = <String, dynamic>{};
      switch (event) {
        case 'model_load.progress':
          extra['progress'] = json['progress']; // 0.0 - 1.0
          break;
        case 'model_load.end':
          extra['loaded'] = true;
          break;
        case 'message.delta':
          fullContent.write(json['content'] as String? ?? '');
          extra['token'] = json['content'];
          extra['token_count'] = (json['token_count'] as int?) ?? 1;
          break;
        case 'message.end':
          extra['token_count'] = json['token_count'];
          extra['finish_reason'] = json['finish_reason'];
          break;
        case 'chat.end':
          extra['total_tokens'] = json['usage']?['total_tokens'];
          extra['prompt_tokens'] = json['usage']?['prompt_tokens'];
          extra['completion_tokens'] = json['usage']?['completion_tokens'];
          break;
        case 'prompt_processing.start':
          break;
        case 'error':
          extra['message'] = json['message'];
          break;
      }
      
      onEvent(event, {...json, ...extra});
    } catch (_) {}
  }
}