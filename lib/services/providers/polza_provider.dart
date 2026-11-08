import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../core/models.dart';
import '../ai_provider.dart';
import '../http_utils.dart';

class PolzaProvider extends AiProvider {
  PolzaProvider({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? 'https://polza.ai/api/v1';

  final http.Client _client;
  final String _baseUrl;

  @override
  AiProviderType get type => AiProviderType.polza;

  Map<String, String> _headers(String apiKey) => {
    'Authorization': 'Bearer $apiKey',
    'Content-Type': 'application/json',
    'accept-language': 'en',
  };

  @override
  Future<void> validateKey({required String apiKey}) async {
    await requestJson(
      _client,
      'GET',
      Uri.parse('$_baseUrl/key'),
      headers: _headers(apiKey),
      timeout: const Duration(seconds: 30),
    );
  }

  String _typeFor(ModelCategory category) => switch (category) {
    ModelCategory.text => 'chat',
    ModelCategory.image => 'image',
    ModelCategory.video => 'video',
  };

  @override
  Future<List<ModelOption>> listModels({
    required String apiKey,
    required ModelCategory category,
  }) async {
    final json = await requestJson(
      _client,
      'GET',
      Uri.parse('$_baseUrl/models?type=${_typeFor(category)}'),
      headers: _headers(apiKey),
      timeout: const Duration(seconds: 45),
    );
    final options = <ModelOption>[];
    final data = json['data'];
    if (data is List) {
      for (final item in data) {
        if (item is! Map) continue;
        final id = item['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        final rawType = item['type']?.toString();
        if (rawType != null && rawType != _typeFor(category)) continue;
        final description = item['short_description'];
        options.add(
          ModelOption(
            provider: type,
            category: category,
            id: id,
            name: item['name']?.toString() ?? id,
            description: description is String ? description : null,
          ),
        );
      }
    }
    options.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return options;
  }

  @override
  Future<ProviderChatResult> chat({
    required String apiKey,
    required String model,
    required List<ChatMessage> messages,
    required ChatToolRuntime runtime,
    CancellationToken? cancellation,
  }) async {
    final tools = _toolDefinitions(runtime);
    final chatMessages = <Map<String, dynamic>>[
      {'role': 'system', 'content': buildSystemPrompt(runtime)},
      ..._buildMessages(messages),
    ];
    final allCitations = <ChatCitation>[];
    final reasoningParts = <String>[];
    var includeReasoning = runtime.reasoning != ReasoningLevel.off;
    var usedWebSearch = false;
    var accumulatedText = '';

    for (var turn = 0; turn < 8; turn++) {
      cancellation?.throwIfCancelled();
      final body = <String, dynamic>{'model': model, 'messages': chatMessages};
      if (tools.isNotEmpty) {
        body['tools'] = tools;
        body['tool_choice'] = 'auto';
      }
      if (runtime.search.isEnabled) {
        body['plugins'] = [
          {
            'id': 'web',
            'engine': 'google',
            'max_results': runtime.search == SearchMode.deep ? 10 : 5,
          },
        ];
      }
      if (includeReasoning) {
        body['reasoning_effort'] = runtime.reasoning == ReasoningLevel.deep
            ? 'high'
            : 'medium';
      }

      Map<String, dynamic> response;
      while (true) {
        try {
          response = await requestJson(
            _client,
            'POST',
            Uri.parse('$_baseUrl/chat/completions'),
            headers: _headers(apiKey),
            body: body,
            timeout: const Duration(minutes: 5),
          );
          cancellation?.throwIfCancelled();
          break;
        } on ApiException catch (error) {
          if (includeReasoning &&
              error.statusCode == 400 &&
              _isParameterError(error.message, 'reasoning')) {
            includeReasoning = false;
            body.remove('reasoning_effort');
            continue;
          }
          rethrow;
        }
      }

      final choices = response['choices'];
      if (choices is! List || choices.isEmpty) {
        throw ApiException(
          extractErrorMessage(response) ?? 'Polza.ai returned no response.',
        );
      }
      final first = choices.first;
      if (first is! Map) {
        throw const ApiException('Polza.ai returned an invalid response.');
      }
      final message = first['message'];
      if (message is! Map) {
        throw const ApiException('Polza.ai returned no message.');
      }
      final map = message.map((k, v) => MapEntry(k.toString(), v));
      final text = _messageText(map['content']);
      if (text.trim().isNotEmpty) accumulatedText = text.trim();
      final reasoning =
          map['reasoning']?.toString() ?? map['reasoning_content']?.toString();
      if (reasoning != null && reasoning.trim().isNotEmpty) {
        if (!reasoningParts.contains(reasoning.trim())) {
          reasoningParts.add(reasoning.trim());
        }
      }
      allCitations.addAll(collectCitations(map['annotations']));
      if (runtime.search.isEnabled && allCitations.isNotEmpty) {
        usedWebSearch = true;
      }

      final rawCalls = map['tool_calls'];
      if (rawCalls is! List || rawCalls.isEmpty) break;

      chatMessages.add(map);
      for (final rawCall in rawCalls) {
        if (rawCall is! Map) continue;
        final call = rawCall.map((k, v) => MapEntry(k.toString(), v));
        final id = call['id']?.toString() ?? '';
        final function = call['function'];
        if (function is! Map) continue;
        final name = function['name']?.toString() ?? '';
        final result = await _executeTool(
          name: name,
          rawArguments: function['arguments'],
          runtime: runtime,
          cancellation: cancellation,
        );
        chatMessages.add({
          'role': 'tool',
          'tool_call_id': id,
          'content': result,
        });
      }
    }

    final finalText = accumulatedText.trim();
    if (finalText.isEmpty) {
      throw const ApiException('The model returned an empty response.');
    }
    return ProviderChatResult(
      text: finalText,
      reasoning: reasoningParts.join('\n\n'),
      citations: allCitations,
      usedWebSearch: usedWebSearch,
    );
  }

  bool _isParameterError(String message, String name) {
    final lower = message.toLowerCase();
    return lower.contains(name) ||
        lower.contains('unsupported') ||
        lower.contains('unknown parameter');
  }

  String _messageText(Object? content) {
    if (content is String) return content;
    if (content is List) {
      final buffer = StringBuffer();
      for (final part in content) {
        if (part is Map && part['text'] is String) {
          buffer.write(part['text']);
        }
      }
      return buffer.toString();
    }
    return '';
  }

  List<Map<String, dynamic>> _buildMessages(List<ChatMessage> messages) {
    final result = <Map<String, dynamic>>[];
    for (final message in messages) {
      if (message.role == ChatRole.assistant) {
        if (message.text.trim().isNotEmpty) {
          result.add({'role': 'assistant', 'content': message.text});
        }
        continue;
      }
      final parts = <Map<String, dynamic>>[];
      if (message.text.trim().isNotEmpty) {
        parts.add({'type': 'text', 'text': message.text});
      }
      for (final attachment in message.attachments) {
        if (attachment.kind == AttachmentKind.image) {
          parts.add({
            'type': 'image_url',
            'image_url': {'url': attachmentDataUri(attachment)},
          });
        } else if (isTextAttachment(attachment)) {
          parts.add({
            'type': 'text',
            'text':
                'File: ${attachment.name}\n\n${readTextAttachment(attachment)}',
          });
        } else if (guessedMimeType(attachment) == 'application/pdf') {
          parts.add({
            'type': 'file',
            'file': {
              'filename': attachment.name,
              'file_data': attachmentDataUri(attachment),
            },
          });
        } else if (attachment.kind == AttachmentKind.video) {
          parts.add({
            'type': 'text',
            'text':
                '[The user attached a local video (${attachment.name}). Polza.ai only accepts videos through public URLs, so it was not sent.]',
          });
        } else {
          parts.add({
            'type': 'text',
            'text':
                '[The user attached ${attachment.name}, which this provider cannot read directly.]',
          });
        }
      }
      if (parts.isEmpty) {
        parts.add({'type': 'text', 'text': '(Empty message)'});
      }
      if (parts.length == 1 && parts.first['type'] == 'text') {
        result.add({'role': 'user', 'content': parts.first['text']});
      } else {
        result.add({'role': 'user', 'content': parts});
      }
    }
    return result;
  }

  List<dynamic> _toolDefinitions(ChatToolRuntime runtime) {
    final tools = <dynamic>[];
    if (runtime.hasImageTool) {
      tools.add({
        'type': 'function',
        'function': {
          'name': 'generate_image',
          'description': 'Generate an image from a detailed text prompt. Use this when the user asks for a new image, illustration, photo or visual.',
          'parameters': {
            'type': 'object',
            'properties': {
              'prompt': {
                'type': 'string',
                'description': 'A detailed image prompt including subject, style, lighting and composition.',
              },
              'aspect_ratio': {
                'type': 'string',
                'enum': ['1:1', '16:9', '9:16', '4:3', '3:4'],
                'description': 'The requested image aspect ratio.',
              },
            },
            'required': ['prompt'],
          },
        },
      });
    }
    if (runtime.hasVideoTool) {
      tools.add({
        'type': 'function',
        'function': {
          'name': 'generate_video',
          'description': 'Generate a short video from a detailed text prompt. Use this only when the user asks for a video.',
          'parameters': {
            'type': 'object',
            'properties': {
              'prompt': {
                'type': 'string',
                'description': 'A cinematic prompt describing the scene, subject, motion, camera and lighting.',
              },
              'aspect_ratio': {
                'type': 'string',
                'enum': ['16:9', '9:16', '1:1'],
                'description': 'The requested video aspect ratio.',
              },
              'duration_seconds': {
                'type': 'integer',
                'enum': [4, 8, 12],
                'description': 'The requested duration in seconds.',
              },
            },
            'required': ['prompt'],
          },
        },
      });
    }
    return tools;
  }

  Future<String> _executeTool({
    required String name,
    required Object? rawArguments,
    required ChatToolRuntime runtime,
    CancellationToken? cancellation,
  }) async {
    try {
      cancellation?.throwIfCancelled();
      Map<String, dynamic> args = const {};
      if (rawArguments is String && rawArguments.trim().isNotEmpty) {
        final decoded = jsonDecode(rawArguments);
        if (decoded is Map<String, dynamic>) args = decoded;
      } else if (rawArguments is Map) {
        args = rawArguments.map((key, value) => MapEntry('$key', value));
      }
      switch (name) {
        case 'generate_image':
          final callback = runtime.generateImage;
          if (callback == null) {
            return toolErrorResult('Image generation is not configured.');
          }
          final prompt = args['prompt']?.toString().trim() ?? '';
          if (prompt.isEmpty) {
            return toolErrorResult('The image prompt is empty.');
          }
          final aspect = _safeAspect(args['aspect_ratio'], const [
            '1:1',
            '16:9',
            '9:16',
            '4:3',
            '3:4',
          ]);
          return toolSuccessResult(await callback(prompt, aspect));
        case 'generate_video':
          final callback = runtime.generateVideo;
          if (callback == null) {
            return toolErrorResult('Video generation is not configured.');
          }
          final prompt = args['prompt']?.toString().trim() ?? '';
          if (prompt.isEmpty) {
            return toolErrorResult('The video prompt is empty.');
          }
          final aspect = _safeAspect(args['aspect_ratio'], const [
            '16:9',
            '9:16',
            '1:1',
          ]);
          final rawDuration = args['duration_seconds'];
          final duration = rawDuration is num
              ? rawDuration.toInt().clamp(4, 12)
              : 8;
          return toolSuccessResult(await callback(prompt, aspect, duration));
        default:
          return toolErrorResult('Unknown tool: $name');
      }
    } on CancellationException {
      rethrow;
    } catch (error) {
      return toolErrorResult(error);
    }
  }

  String _safeAspect(Object? value, List<String> allowed) {
    final text = value?.toString();
    if (text != null && allowed.contains(text)) return text;
    return allowed.first;
  }

  @override
  Future<GeneratedMedia> generateImage({
    required String apiKey,
    required String model,
    required String prompt,
    required String aspectRatio,
    ImageResolution resolution = ImageResolution.oneK,
    CancellationToken? cancellation,
  }) async {
    final input = <String, dynamic>{
      'prompt': prompt,
      'aspect_ratio': _safeAspect(aspectRatio, const [
        '1:1',
        '16:9',
        '9:16',
        '4:3',
        '3:4',
      ]),
    };
    // Polza validates image_resolution against the model catalog. Only send
    // it when a higher resolution was picked so models that do not list the
    // parameter (like Z-Image) keep their default behaviour.
    if (resolution != ImageResolution.oneK) {
      input['image_resolution'] = resolution.apiValue;
    }
    final json = await _generateMedia(
      apiKey: apiKey,
      body: {'model': model, 'input': input},
      maxWait: const Duration(minutes: 8),
      image: true,
      cancellation: cancellation,
    );
    return _mediaFromResponse(json, image: true, cancellation: cancellation);
  }

  @override
  Future<GeneratedMedia> generateVideo({
    required String apiKey,
    required String model,
    required String prompt,
    required String aspectRatio,
    required int seconds,
    CancellationToken? cancellation,
  }) async {
    final json = await _generateMedia(
      apiKey: apiKey,
      body: {
        'model': model,
        'input': {
          'prompt': prompt,
          'aspect_ratio': _safeAspect(aspectRatio, const [
            '16:9',
            '9:16',
            '1:1',
          ]),
          'duration': '${seconds.clamp(3, 15)}',
        },
      },
      maxWait: const Duration(minutes: 20),
      image: false,
      cancellation: cancellation,
    );
    return _mediaFromResponse(json, image: false, cancellation: cancellation);
  }

  static const _completedStatuses = {
    'completed',
    'complete',
    'succeeded',
    'success',
    'done',
    'finished',
  };

  static const _mediaUrlKeys = [
    'url',
    'uri',
    'download_url',
    'file_url',
    'image_url',
    'video_url',
    'media_url',
    'signed_url',
  ];

  static const _mediaBase64Keys = [
    'b64_json',
    'base64',
    'image_base64',
    'video_base64',
    'data_base64',
  ];

  static const _mediaContainerKeys = [
    'data',
    'output',
    'outputs',
    'result',
    'results',
    'media',
    'images',
    'videos',
    'files',
    'artifacts',
    'assets',
    'response',
    'generations',
  ];

  Future<Map<String, dynamic>> _generateMedia({
    required String apiKey,
    required Map<String, dynamic> body,
    required Duration maxWait,
    required bool image,
    CancellationToken? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    var json = await requestJson(
      _client,
      'POST',
      Uri.parse('$_baseUrl/media'),
      headers: _headers(apiKey),
      body: body,
      timeout: const Duration(minutes: 5),
    );
    cancellation?.throwIfCancelled();
    final deadline = DateTime.now().add(maxWait);
    final interval = Duration(seconds: image ? 4 : 7);
    var lastStatus = '';
    while (true) {
      final status = _mediaStatus(json);
      if (status != null) lastStatus = status;
      if (status == null || _completedStatuses.contains(status)) {
        if (_hasMedia(json)) return json;
        if (status != null) {
          // The provider reports the job as finished but delivered no file.
          // Polling again would not change that; fail clearly instead of
          // spinning until the timeout.
          throw ApiException(
            extractErrorMessage(json) ?? 'Polza.ai reported the generation as finished but returned no media file.',
          );
        }
        // No status field at all: treat the response as final and let the
        // caller report a missing file honestly.
        return json;
      }
      if (status == 'failed' || status == 'error') {
        throw ApiException(
          extractErrorMessage(json) ??
              json['error']?.toString() ??
              'Polza.ai media generation failed.',
        );
      }
      if (status == 'cancelled') {
        throw const ApiException('Polza.ai media generation was cancelled.');
      }
      final id = _mediaJobId(json);
      if (id == null || id.isEmpty) {
        throw ApiException(
          extractErrorMessage(json) ??
              'Polza.ai returned no media job information.',
        );
      }
      if (DateTime.now().isAfter(deadline)) {
        throw ApiException(
          lastStatus.isEmpty
              ? 'Timed out while waiting for the media.'
              : 'Timed out while waiting for the media (last status: $lastStatus).',
        );
      }
      cancellation?.throwIfCancelled();
      await Future<void>.delayed(interval);
      cancellation?.throwIfCancelled();
      json = await requestJson(
        _client,
        'GET',
        Uri.parse('$_baseUrl/media/$id'),
        headers: _headers(apiKey),
        timeout: const Duration(seconds: 60),
      );
      cancellation?.throwIfCancelled();
    }
  }

  String? _mediaStatus(Map<String, dynamic> json) {
    final top = json['status']?.toString().toLowerCase().trim();
    if (top != null && top.isNotEmpty) return top;
    final data = json['data'];
    if (data is Map) {
      final nested = data['status']?.toString().toLowerCase().trim();
      if (nested != null && nested.isNotEmpty) return nested;
    }
    return null;
  }

  String? _mediaJobId(Map<String, dynamic> json) {
    for (final key in const ['id', 'job_id', 'generation_id', 'task_id']) {
      final value = json[key]?.toString();
      if (value != null && value.isNotEmpty) return value;
    }
    final data = json['data'];
    if (data is Map) {
      for (final key in const ['id', 'job_id', 'generation_id', 'task_id']) {
        final value = data[key]?.toString();
        if (value != null && value.isNotEmpty) return value;
      }
    }
    return null;
  }

  bool _hasMedia(Map<String, dynamic> json) {
    return _mediaUrl(json) != null || _mediaBase64(json) != null;
  }

  String? _mediaUrl(Map<String, dynamic> json) {
    return _findMediaUrl(json, 0, <Object>{});
  }

  String? _findMediaUrl(Object? node, int depth, Set<Object> visited) {
    if (node == null || depth > 8) return null;
    if (node is String) return _asMediaUrl(node);
    if (node is! Map && node is! List) return null;
    if (!visited.add(node)) return null;
    try {
      if (node is List) {
        for (final item in node) {
          final url = _findMediaUrl(item, depth + 1, visited);
          if (url != null) return url;
        }
        return null;
      }
      if (node is! Map) return null;
      final map = node.map((key, value) => MapEntry('$key', value));
      for (final key in _mediaUrlKeys) {
        final url = _asMediaUrl(map[key]);
        if (url != null) return url;
      }
      for (final key in _mediaContainerKeys) {
        if (!map.containsKey(key)) continue;
        final url = _findMediaUrl(map[key], depth + 1, visited);
        if (url != null) return url;
      }
      for (final value in map.values) {
        final url = _findMediaUrl(value, depth + 1, visited);
        if (url != null) return url;
      }
      return null;
    } finally {
      visited.remove(node);
    }
  }

  String? _asMediaUrl(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    return null;
  }

  String? _mediaBase64(Map<String, dynamic> json) {
    return _findMediaBase64(json, 0, <Object>{});
  }

  String? _findMediaBase64(Object? node, int depth, Set<Object> visited) {
    if (node == null || depth > 8) return null;
    if (node is String) return _asBase64(node);
    if (node is! Map && node is! List) return null;
    if (!visited.add(node)) return null;
    try {
      if (node is List) {
        for (final item in node) {
          final base64 = _findMediaBase64(item, depth + 1, visited);
          if (base64 != null) return base64;
        }
        return null;
      }
      if (node is! Map) return null;
      final map = node.map((key, value) => MapEntry('$key', value));
      for (final key in _mediaBase64Keys) {
        final base64 = _asBase64(map[key], explicitKey: true);
        if (base64 != null) return base64;
      }
      // A data URI may hide in the usual URL fields.
      for (final key in _mediaUrlKeys) {
        final value = map[key];
        if (value is String && value.trim().startsWith('data:')) {
          return _asBase64(value);
        }
      }
      for (final key in _mediaContainerKeys) {
        if (!map.containsKey(key)) continue;
        final base64 = _findMediaBase64(map[key], depth + 1, visited);
        if (base64 != null) return base64;
      }
      for (final value in map.values) {
        final base64 = _findMediaBase64(value, depth + 1, visited);
        if (base64 != null) return base64;
      }
      return null;
    } finally {
      visited.remove(node);
    }
  }

  String? _asBase64(Object? value, {bool explicitKey = false}) {
    if (value is! String) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('data:')) {
      final separator = trimmed.indexOf(',');
      if (separator < 0) return null;
      final payload = trimmed.substring(separator + 1).trim();
      return payload.isEmpty ? null : payload;
    }
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return null;
    }
    // Generic strings must be long enough to actually look like media data;
    // explicit base64 fields are trusted by name.
    if (!explicitKey && trimmed.length < 64) return null;
    return RegExp(r'^[A-Za-z0-9+/=\s]+$').hasMatch(trimmed) ? trimmed : null;
  }

  String? _mediaMime(Map<String, dynamic> json) {
    String? find(Object? node, int depth) {
      if (node == null || depth > 6) return null;
      if (node is Map) {
        final map = node.map((key, value) => MapEntry('$key', value));
        for (final key in const [
          'content_type',
          'mime_type',
          'mimeType',
          'content-type',
        ]) {
          final value = map[key]?.toString();
          if (value != null &&
              (value.startsWith('image/') || value.startsWith('video/'))) {
            return value.split(';').first;
          }
        }
        for (final value in map.values) {
          final found = find(value, depth + 1);
          if (found != null) return found;
        }
      } else if (node is List) {
        for (final item in node) {
          final found = find(item, depth + 1);
          if (found != null) return found;
        }
      }
      return null;
    }

    return find(json, 0);
  }

  Future<GeneratedMedia> _mediaFromResponse(
    Map<String, dynamic> json, {
    required bool image,
    CancellationToken? cancellation,
  }) async {
    final url = _mediaUrl(json);
    Uint8List bytes;
    String mime;
    if (url != null) {
      cancellation?.throwIfCancelled();
      final request = http.Request('GET', Uri.parse(url));
      final response = await rawRequest(
        _client,
        request,
        timeout: const Duration(minutes: 3),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          'Could not download the generated media (HTTP ${response.statusCode}).',
          statusCode: response.statusCode,
        );
      }
      bytes = Uint8List.fromList(response.bodyBytes);
      final contentType = response.headers['content-type'] ?? '';
      mime =
          contentType.startsWith('image/') || contentType.startsWith('video/')
          ? contentType.split(';').first
          : (_mediaMime(json) ?? (image ? 'image/png' : 'video/mp4'));
    } else {
      final base64 = _mediaBase64(json);
      if (base64 == null) {
        throw const ApiException('Polza.ai returned no media file.');
      }
      cancellation?.throwIfCancelled();
      try {
        bytes = base64Decode(base64);
      } on FormatException {
        throw const ApiException(
          'Polza.ai returned media data that could not be decoded.',
        );
      }
      mime = _mediaMime(json) ?? (image ? 'image/png' : 'video/mp4');
    }
    return GeneratedMedia(
      bytes: bytes,
      mimeType: mime,
      extension: switch (mime) {
        'image/jpeg' || 'image/jpg' => 'jpg',
        'image/webp' => 'webp',
        'video/webm' => 'webm',
        'video/mp4' => 'mp4',
        _ => image ? 'png' : 'mp4',
      },
    );
  }
}
