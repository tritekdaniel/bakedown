import 'dart:async';
import 'dart:convert';
import 'dart:io' if (dart.library.html) 'package:recipe_app/shared/stubs/io_stub.dart';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:recipe_app/core/constants/app_constants.dart';
import '../../domain/models/lm_studio_model.dart';

const _timeout = Duration(seconds: 120);
const _quickTimeout = Duration(seconds: 5);

final _sharedDio = Dio(BaseOptions(
  connectTimeout: const Duration(seconds: 15),
  receiveTimeout: _quickTimeout,
));

final _longDio = Dio(BaseOptions(
  connectTimeout: const Duration(seconds: 15),
  receiveTimeout: _timeout,
));

Dio _dio({Duration? receiveTimeout}) {
  if (receiveTimeout == null || receiveTimeout == _quickTimeout) return _sharedDio;
  if (receiveTimeout == _timeout) return _longDio;
  return Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: receiveTimeout,
  ));
}

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

String _extractMessageFromV1Output(dynamic output) {
  if (output == null) return '';
  if (output is String) return output;
  if (output is Map<String, dynamic>) {
    final c = output['content'] as String?;
    if (c != null && c.isNotEmpty) return c;
    return '';
  }
  if (output is List) {
    final messages = <String>[];
    String? fallback;
    for (final item in output) {
      if (item is! Map) continue;
      final map = item as Map<String, dynamic>;
      final type = map['type'] as String?;
      final content = map['content'] as String? ?? map['text'] as String? ?? '';
      if (type == 'message' && content.isNotEmpty) {
        messages.add(content);
      } else if (type == 'reasoning') {
        continue;
      } else if (content.isNotEmpty && fallback == null) {
        fallback = content;
      }
    }
    if (messages.isNotEmpty) return messages.join('\n');
    return fallback ?? '';
  }
  return '';
}

class LmStudioRepository {
  final String baseUrl;

  LmStudioRepository(String url) : baseUrl = AppConstants.normalizeUrl(url);

  Future<Response<dynamic>?> _getWithFallback(String primary, String fallback) async {
    try {
      final resp = await _dio().get('$baseUrl$primary', options: Options(validateStatus: (_) => true));
      if (resp.statusCode == 200) return resp;
      if (resp.statusCode == 404) {
        final alt = await _dio().get('$baseUrl$fallback', options: Options(validateStatus: (_) => true));
        if (alt.statusCode == 200) return alt;
      }
      return resp;
    } catch (_) {
      try {
        final alt = await _dio().get('$baseUrl$fallback', options: Options(validateStatus: (_) => true));
        if (alt.statusCode == 200) return alt;
      } catch (_) {}
      return null;
    }
  }

  List<LmStudioModel> _parseModelsResponse(dynamic data) {
    if (data is! Map<String, dynamic>) return [];
    final raw = data['models'] as List<dynamic>? ?? data['data'] as List<dynamic>? ?? [];
    return raw.map((m) => LmStudioModel.fromJson(m as Map<String, dynamic>)).toList();
  }

  Future<ConnectionTestResult> testConnection() async {
    final stopwatch = Stopwatch()..start();
    try {
      final response = await _getWithFallback('/api/v1/models', '/v1/models');
      stopwatch.stop();
      if (response != null && response.statusCode == 200) {
        final models = _parseModelsResponse(response.data);
        return ConnectionTestResult(
          success: true,
          statusCode: 200,
          modelCount: models.length,
          url: baseUrl,
          elapsed: stopwatch.elapsed,
        );
      }
      if (response != null) {
        return ConnectionTestResult(
          success: false,
          statusCode: response.statusCode,
          url: baseUrl,
          elapsed: stopwatch.elapsed,
        );
      }
      return ConnectionTestResult(success: false, error: 'No response', url: baseUrl, elapsed: stopwatch.elapsed);
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
          detail += '\nTip: on mobile use http://<PC-LAN-IP>:1234 not localhost.';
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
      final response = await _getWithFallback('/api/v1/models', '/v1/models');
      if (response != null && response.statusCode == 200) {
        return _parseModelsResponse(response.data);
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
      final response = await _getWithFallback('/api/v1/models', '/v1/models');
      if (response != null && response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final raw = data['models'] as List<dynamic>? ?? data['data'] as List<dynamic>? ?? [];
        final loadedIds = <String>[];
        for (final m in raw) {
          final map = m as Map<String, dynamic>;
          final instances = map['loaded_instances'] as List<dynamic>?;
          if (instances != null) {
            for (final inst in instances) {
              loadedIds.add(inst['id'] as String);
            }
          } else if (map['id'] != null && (map['object'] == 'model' || map['state'] == 'loaded')) {
            loadedIds.add(map['id'] as String);
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
    List<Uint8List>? imageBytesList,
    List<String>? imageNames,
    String? textContent,
    required SseEventHandler onEvent,
    CancelToken? cancelToken,
  }) async {
    try {
      final hasBytes = imageBytesList != null && imageBytesList.isNotEmpty;
      final hasPaths = imagePaths != null && imagePaths.isNotEmpty;
      if (!hasBytes && !hasPaths && textContent == null) return null;

      final useStream = !kIsWeb;
      String? result;

      Future<String?> tryNewApi() async {
        dynamic input;
        if (hasBytes || hasPaths) {
          final parts = <Map<String, dynamic>>[
            {
              'type': 'text',
              'content':
                  'Transcribe these recipe images into the required markdown format. Output ONLY the final markdown starting with ---, no chain-of-thought, no <think> tags, no preamble or explanation.'
            },
          ];
          if (hasBytes) {
            for (var i = 0; i < imageBytesList!.length; i++) {
              try {
                final bytes = imageBytesList[i];
                final name = (imageNames != null && i < imageNames.length) ? imageNames[i] : 'image.jpg';
                final ext = name.split('.').last.toLowerCase();
                final mimeType = ext == 'png' ? 'image/png' : ext == 'webp' ? 'image/webp' : 'image/jpeg';
                parts.add({'type': 'image', 'data_url': 'data:$mimeType;base64,${base64Encode(bytes)}'});
              } catch (_) {}
            }
          } else {
            for (final path in imagePaths!) {
              try {
                final imageBytes = await File(path).readAsBytes();
                final base64Image = base64Encode(imageBytes);
                final ext = path.split('.').last.toLowerCase();
                final mimeType = ext == 'png' ? 'image/png' : 'image/jpeg';
                parts.add({'type': 'image', 'data_url': 'data:$mimeType;base64,$base64Image'});
              } catch (_) {}
            }
          }
          input = parts;
        } else {
          input =
              'Re-format this recipe into the required markdown format. Output ONLY the final markdown starting with ---, no chain-of-thought, no <think> tags, no preamble.\n\n$textContent';
        }
        final body = {
          'model': modelId,
          'input': input,
          'system_prompt': systemPrompt,
          'stream': useStream,
          'temperature': 0.1,
          'max_output_tokens': 8192,
          'reasoning': 'off',
          'store': false,
        };
        if (!useStream) {
          final resp = await _dio(receiveTimeout: _timeout).post(
            '$baseUrl/api/v1/chat',
            data: body,
            options: Options(validateStatus: (_) => true),
            cancelToken: cancelToken,
          );
          if (resp.statusCode == 404) return null;
          if (resp.statusCode != 200) {
            final err = resp.data is Map
                ? (resp.data['error']?.toString() ?? resp.data['message']?.toString() ?? 'HTTP ${resp.statusCode}')
                : 'HTTP ${resp.statusCode} ${resp.data}';
            onEvent('error', {'message': err, 'url': '$baseUrl/api/v1/chat'});
            return '__error__';
          }
          final data = resp.data;
          String content = '';
          if (data is Map<String, dynamic>) {
            if (data['output'] != null) {
              content = _extractMessageFromV1Output(data['output']);
            }
            if (content.isEmpty && data['choices'] is List && (data['choices'] as List).isNotEmpty) {
              final first = (data['choices'] as List)[0];
              if (first is Map) {
                final msg = first['message'];
                if (msg is Map) content = msg['content'] as String? ?? '';
                content = content.isNotEmpty ? content : (first['text'] as String? ?? '');
              }
            }
            if (content.isEmpty) {
              content = data['content'] as String? ?? '';
            }
            if (content.isNotEmpty) onEvent('message.delta', {'content': content, 'token_count': content.length});
            onEvent('message.end', {'finish_reason': 'stop'});
            onEvent('chat.end', {'usage': data['usage']});
          }
          return content.isNotEmpty ? content : '__empty__';
        }
        final response = await _dio(receiveTimeout: _timeout).post<ResponseBody>(
          '$baseUrl/api/v1/chat',
          data: body,
          options: Options(responseType: ResponseType.stream, validateStatus: (_) => true),
          cancelToken: cancelToken,
        );
        if (response.statusCode == 404) return null;
        if (response.statusCode != 200) {
          String errBody = '';
          try {
            final bytes = <int>[];
            await for (final chunk in response.data!.stream) bytes.addAll(chunk);
            if (bytes.isNotEmpty) errBody = utf8.decode(bytes);
          } catch (_) {}
          final err = errBody.isNotEmpty ? errBody : 'HTTP ${response.statusCode}';
          onEvent('error', {'message': err, 'url': '$baseUrl/api/v1/chat'});
          return '__error__';
        }
        return await _consumeSseStream(response.data!.stream, onEvent);
      }

      Future<String?> tryLegacyApi() async {
        List<Map<String, dynamic>> messages = [];
        messages.add({'role': 'system', 'content': systemPrompt});
        if (hasBytes || hasPaths) {
          final contentParts = <Map<String, dynamic>>[
            {
              'type': 'text',
              'text':
                  'Transcribe these recipe images into the required markdown format. Output ONLY the final markdown starting with ---, no chain-of-thought, no <think> tags, no preamble or explanation.'
            },
          ];
          if (hasBytes) {
            for (var i = 0; i < imageBytesList!.length; i++) {
              final bytes = imageBytesList[i];
              final name = (imageNames != null && i < imageNames.length) ? imageNames[i] : 'image.jpg';
              final ext = name.split('.').last.toLowerCase();
              final mimeType = ext == 'png' ? 'image/png' : ext == 'webp' ? 'image/webp' : 'image/jpeg';
              contentParts.add({
                'type': 'image_url',
                'image_url': {'url': 'data:$mimeType;base64,${base64Encode(bytes)}'}
              });
            }
          } else {
            for (final path in imagePaths!) {
              final imageBytes = await File(path).readAsBytes();
              final base64Image = base64Encode(imageBytes);
              final ext = path.split('.').last.toLowerCase();
              final mimeType = ext == 'png' ? 'image/png' : 'image/jpeg';
              contentParts.add({
                'type': 'image_url',
                'image_url': {'url': 'data:$mimeType;base64,$base64Image'}
              });
            }
          }
          messages.add({'role': 'user', 'content': contentParts});
        } else {
          messages.add({
            'role': 'user',
            'content':
                'Re-format this recipe into the required markdown format. Output ONLY the final markdown starting with ---, no chain-of-thought, no <think> tags, no preamble.\n\n$textContent'
          });
        }
        final body = {
          'model': modelId,
          'messages': messages,
          'stream': useStream,
          'temperature': 0.1,
          'max_tokens': 8192,
        };
        if (!useStream) {
          final resp = await _dio(receiveTimeout: _timeout).post(
            '$baseUrl/v1/chat/completions',
            data: body,
            options: Options(validateStatus: (_) => true),
            cancelToken: cancelToken,
          );
          if (resp.statusCode != 200) {
            final err = resp.data is Map ? (resp.data['error']?.toString() ?? 'HTTP ${resp.statusCode}') : 'HTTP ${resp.statusCode} ${resp.data}';
            onEvent('error', {'message': err, 'url': '$baseUrl/v1/chat/completions'});
            return '__error__';
          }
          final data = resp.data as Map<String, dynamic>;
          String content = '';
          if (data['choices'] is List && (data['choices'] as List).isNotEmpty) {
            final choice = (data['choices'] as List)[0] as Map;
            content = (choice['message']?['content'] as String?) ?? (choice['text'] as String?) ?? '';
          }
          if (content.isNotEmpty) onEvent('message.delta', {'content': content, 'token_count': content.length});
          onEvent('message.end', {'finish_reason': 'stop'});
          onEvent('chat.end', {'usage': data['usage']});
          return content.isNotEmpty ? content : '__empty__';
        }
        final response = await _dio(receiveTimeout: _timeout).post<ResponseBody>(
          '$baseUrl/v1/chat/completions',
          data: body,
          options: Options(responseType: ResponseType.stream, validateStatus: (_) => true),
          cancelToken: cancelToken,
        );
        if (response.statusCode != 200) {
          String errBody = '';
          try {
            final bytes = <int>[];
            await for (final chunk in response.data!.stream) bytes.addAll(chunk);
            if (bytes.isNotEmpty) errBody = utf8.decode(bytes);
          } catch (_) {}
          final err = errBody.isNotEmpty ? errBody : 'HTTP ${response.statusCode}';
          onEvent('error', {'message': err, 'url': '$baseUrl/v1/chat/completions'});
          return '__error__';
        }
        return await _consumeSseStream(response.data!.stream, onEvent);
      }

      result = await tryNewApi();
      if (result == null) {
        result = await tryLegacyApi();
      }
      if (result == '__empty__' || result == '__error__') return null;
      return result;
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
          await for (final chunk in errBody.stream) bytes.addAll(chunk);
          if (bytes.isNotEmpty) msg = '${e.response?.statusCode}: ${utf8.decode(bytes)}';
        } catch (_) {}
      }
      onEvent('error', {'message': msg});
      return null;
    }
  }

  Future<String?> _consumeSseStream(Stream<Uint8List> stream, SseEventHandler onEvent) async {
    final fullContent = StringBuffer();
    String? chatEndResult;
    var sseBuffer = '';
    var sseEvent = '';
    var sseData = '';

    void flushEvent() {
      if (sseData.isEmpty) {
        sseEvent = '';
        return;
      }
      if (sseData == '[DONE]') {
        onEvent('message.end', {'finish_reason': 'stop'});
        onEvent('chat.end', {});
        sseEvent = '';
        sseData = '';
        return;
      }
      final eventToUse = sseEvent.isNotEmpty ? sseEvent : 'data';
      final captured = _handleSseEvent(eventToUse, sseData, onEvent, fullContent);
      if (captured != null) chatEndResult = captured;
      sseEvent = '';
      sseData = '';
    }

    await for (final chunk in stream) {
      final text = utf8.decode(chunk, allowMalformed: true);
      sseBuffer += text;
      final lines = sseBuffer.split('\n');
      sseBuffer = lines.removeLast();
      for (final line in lines) {
        if (line.startsWith('event: ')) {
          sseEvent = line.substring(7).trim();
        } else if (line.startsWith('data: ')) {
          final dataPart = line.substring(6);
          if (dataPart.trim() == '[DONE]') {
            sseData = '[DONE]';
            flushEvent();
          } else {
            if (sseData.isNotEmpty) sseData += '\n';
            sseData += dataPart;
          }
        } else if (line.trim().isEmpty) {
          flushEvent();
        } else if (line.startsWith(':')) {
        } else {
          if (sseData.isNotEmpty) sseData += '\n';
          sseData += line;
        }
      }
    }
    if (sseBuffer.trim().isNotEmpty) {
      if (sseBuffer.startsWith('data: ')) {
        sseData = sseBuffer.substring(6).trim();
        flushEvent();
      } else if (sseBuffer.trim() == '[DONE]') {
        sseData = '[DONE]';
        flushEvent();
      }
    } else if (sseData.isNotEmpty) {
      flushEvent();
    }
    if (chatEndResult != null && chatEndResult!.isNotEmpty) {
      final deltaLen = fullContent.length;
      if (deltaLen == 0 || chatEndResult!.length > deltaLen || !chatEndResult!.startsWith(fullContent.toString().substring(0, (deltaLen * 0.8).floor().clamp(0, deltaLen)))) {
        return chatEndResult;
      }
    }
    final result = fullContent.toString();
    return result.isNotEmpty ? result : chatEndResult;
  }

  String? _handleSseEvent(String event, String data, SseEventHandler onEvent, StringBuffer fullContent) {
    try {
      if (data.trim() == '[DONE]') {
        onEvent('message.end', {'finish_reason': 'stop'});
        onEvent('chat.end', {});
        return null;
      }
      final json = jsonDecode(data) as Map<String, dynamic>;

      if (json.containsKey('choices')) {
        final choices = json['choices'] as List<dynamic>?;
        if (choices != null && choices.isNotEmpty) {
          final choice = choices[0] as Map<String, dynamic>;
          final delta = choice['delta'] as Map<String, dynamic>?;
          final message = choice['message'] as Map<String, dynamic>?;
          String? chunk;
          if (delta != null) chunk = delta['content'] as String?;
          chunk ??= message?['content'] as String?;
          chunk ??= choice['text'] as String?;
          if (chunk != null && chunk.isNotEmpty) {
            fullContent.write(chunk);
            onEvent('message.delta', {'content': chunk, 'token_count': chunk.length, ...json});
          }
          final finish = choice['finish_reason'] as String?;
          if (finish != null) {
            onEvent('message.end', {'finish_reason': finish, ...json});
            if (json.containsKey('usage')) onEvent('chat.end', {'usage': json['usage']});
          }
          if (json.containsKey('usage')) onEvent('chat.end', {'usage': json['usage']});
          return null;
        }
      }

      final extra = <String, dynamic>{};
      switch (event) {
        case 'model_load.progress':
          extra['progress'] = json['progress'];
          break;
        case 'model_load.end':
          extra['loaded'] = true;
          break;
        case 'reasoning.start':
        case 'reasoning.delta':
        case 'reasoning.end':
          break;
        case 'message.delta':
          final content = json['content'] as String? ?? json['delta'] as String? ?? '';
          if (content.isNotEmpty) fullContent.write(content);
          extra['token'] = content;
          extra['token_count'] = (json['token_count'] as int?) ?? content.length.clamp(1, 9999);
          break;
        case 'message.start':
          break;
        case 'message.end':
          extra['token_count'] = json['token_count'];
          extra['finish_reason'] = json['finish_reason'];
          break;
        case 'chat.end':
          final result = json['result'] as Map<String, dynamic>?;
          final output = result?['output'];
          final extracted = _extractMessageFromV1Output(output);
          if (extracted.isNotEmpty) {
            extra['total_tokens'] = result?['stats']?['total_output_tokens'] ?? json['usage']?['total_tokens'];
            onEvent(event, {...json, ...extra});
            return extracted;
          }
          extra['total_tokens'] = json['usage']?['total_tokens'] ?? result?['stats']?['total_output_tokens'];
          extra['prompt_tokens'] = json['usage']?['prompt_tokens'];
          extra['completion_tokens'] = json['usage']?['completion_tokens'];
          break;
        case 'prompt_processing.start':
          break;
        case 'error':
          final errObj = json['error'];
          if (errObj is Map) {
            extra['message'] = errObj['message']?.toString() ?? json['message']?.toString();
          } else {
            extra['message'] = json['message'] ?? json['error']?.toString();
          }
          break;
        case 'data':
          if (json['content'] != null) {
            final c = json['content'] as String;
            fullContent.write(c);
            onEvent('message.delta', {'content': c, 'token_count': c.length, ...json});
            return null;
          }
          break;
      }
      onEvent(event, {...json, ...extra});
      return null;
    } catch (_) {
      return null;
    }
  }
}
