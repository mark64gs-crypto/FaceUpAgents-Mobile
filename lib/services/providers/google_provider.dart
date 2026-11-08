import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../core/models.dart';
import '../ai_provider.dart';
import '../http_utils.dart';

class GoogleProvider extends AiProvider {
  GoogleProvider({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? 'https://generativelanguage.googleapis.com/v1beta';

  final http.Client _client;
  final String _baseUrl;

  @override
  AiProviderType get type => AiProviderType.google;

  Map<String, String> _headers(String apiKey) => {
    'x-goog-api-key': apiKey,
    'Content-Type': 'application/json',
  };

  @override
  Future<void> validateKey({required String apiKey}) async {
    await requestJson(
      _client,
      'GET',
      Uri.parse('$_baseUrl/models?pageSize=1'),
      headers: _headers(apiKey),
      timeout: const Duration(seconds: 30),
    );
  }

  @override
  Future<List<ModelOption>> listModels({
    required String apiKey,
    required ModelCategory category,
  }) async {
    final json = await requestJson(
      _client,
      'GET',
      Uri.parse('$_baseUrl/models?pageSize=1000'),
      headers: _headers(apiKey),
      timeout: const Duration(seconds: 30),
    );
    final options = <ModelOption>[];
    final rawModels = json['models'];
    if (rawModels is List) {
      for (final item in rawModels) {
        if (item is! Map) continue;
        final rawName = item['name']?.toString() ?? '';
        final id = rawName.startsWith('models/')
            ? rawName.substring('models/'.length)
            : rawName;
        if (id.isEmpty) continue;
        if (!_matchesCategory(id, category)) continue;
        options.add(
          ModelOption(
            provider: type,
            category: category,
            id: id,
            name: item['displayName']?.toString() ?? id,
            description: item['description']?.toString(),
          ),
        );
      }
    }
    if (options.isEmpty) {
      final fallback = switch (category) {
        ModelCategory.text => const <String>[],
        ModelCategory.image => const <String>[
          'gemini-nano-banana-2.1',
          'gemini-3-pro-image',
          'gemini-3.1-flash-image',
          'gemini-2.5-flash-image',
        ],
        ModelCategory.video => const <String>['gemini-omni-1.2-flash'],
      };
      for (final id in fallback) {
        options.add(
          ModelOption(provider: type, category: category, id: id, name: id),
        );
      }
    }
    return options;
  }

  bool _matchesCategory(String id, ModelCategory category) {
    final lower = id.toLowerCase();
    if (lower.contains('embedding') ||
        lower.contains('tts') ||
        lower.contains('audio') ||
        lower.contains('learnlm') ||
        lower.contains('aqa')) {
      return false;
    }
    return switch (category) {
      ModelCategory.text =>
        (lower.startsWith('gemini-') || lower.startsWith('gemma-')) &&
            !lower.contains('image') &&
            !lower.contains('imagen') &&
            !lower.contains('veo') &&
            !lower.contains('omni'),
      ModelCategory.image =>
        lower.contains('image') || lower.startsWith('imagen'),
      ModelCategory.video => lower.contains('veo') || lower.contains('omni'),
    };
  }

  @override
  Future<ProviderChatResult> chat({
    required String apiKey,
    required String model,
    required List<ChatMessage> messages,
    required ChatToolRuntime runtime,
    CancellationToken? cancellation,
  }) async {
    final contents = _buildContents(messages);
    final functionDeclarations = _functionDeclarations(runtime);
    final allCitations = <ChatCitation>[];
    final reasoningParts = <String>[];
    var usedWebSearch = false;
    var includeThinking = runtime.reasoning != ReasoningLevel.off;
    var accumulatedText = '';

    for (var turn = 0; turn < 8; turn++) {
      cancellation?.throwIfCancelled();
      final tools = <Map<String, dynamic>>[];
      if (functionDeclarations.isNotEmpty) {
        tools.add({'functionDeclarations': functionDeclarations});
      }
      if (runtime.search.isEnabled) {
        tools.add({'googleSearch': <String, dynamic>{}});
      }
      final body = <String, dynamic>{
        'systemInstruction': {
          'parts': [
            {'text': buildSystemPrompt(runtime)},
          ],
        },
        'contents': contents,
      };
      if (tools.isNotEmpty) body['tools'] = tools;
      if (includeThinking) {
        body['generationConfig'] = {
          'thinkingConfig': {
            'includeThoughts': true,
            'thinkingBudget': runtime.reasoning == ReasoningLevel.deep
                ? 24576
                : 4096,
          },
        };
      }

      Map<String, dynamic> response;
      while (true) {
        try {
          response = await requestJson(
            _client,
            'POST',
            Uri.parse('$_baseUrl/models/${_modelPath(model)}:generateContent'),
            headers: _headers(apiKey),
            body: body,
            timeout: const Duration(minutes: 5),
          );
          cancellation?.throwIfCancelled();
          break;
        } on ApiException catch (error) {
          if (includeThinking &&
              error.statusCode == 400 &&
              _isParameterError(error.message)) {
            includeThinking = false;
            body.remove('generationConfig');
            continue;
          }
          rethrow;
        }
      }

      final candidates = response['candidates'];
      if (candidates is! List || candidates.isEmpty) {
        final feedback = response['promptFeedback'];
        if (feedback is Map && feedback['blockReason'] != null) {
          throw ApiException(
            'Google blocked this request: ${feedback['blockReason']}.',
          );
        }
        throw const ApiException('Google returned no response candidates.');
      }
      final candidate = candidates.first;
      if (candidate is! Map) {
        throw const ApiException('Google returned an invalid response.');
      }
      final content = candidate['content'];
      final parts = <Map<String, dynamic>>[];
      final functionCalls = <Map<String, dynamic>>[];
      final responseText = <String>[];
      if (content is Map && content['parts'] is List) {
        for (final rawPart in content['parts'] as List) {
          if (rawPart is! Map) continue;
          final part = rawPart.map((k, v) => MapEntry(k.toString(), v));
          parts.add(part);
          if (part['functionCall'] is Map) {
            final call = (part['functionCall'] as Map).map(
              (k, v) => MapEntry(k.toString(), v),
            );
            functionCalls.add(call);
          } else if (part['text'] is String) {
            final text = part['text'] as String;
            if (part['thought'] == true) {
              final thought = text.trim();
              if (thought.isNotEmpty && !reasoningParts.contains(thought)) {
                reasoningParts.add(thought);
              }
            } else {
              responseText.add(text);
            }
          }
        }
      }
      if (responseText.isNotEmpty) {
        accumulatedText = responseText.join().trim();
      }
      allCitations.addAll(collectCitations(response));
      final grounding = candidate['groundingMetadata'];
      if (grounding is Map && runtime.search.isEnabled) usedWebSearch = true;
      if (allCitations.isNotEmpty) usedWebSearch = true;

      if (functionCalls.isEmpty) break;

      contents.add({'role': 'model', 'parts': parts});
      final responseParts = <Map<String, dynamic>>[];
      for (final call in functionCalls) {
        final name = call['name']?.toString() ?? '';
        final result = await _executeTool(
          name: name,
          arguments: call['args'],
          runtime: runtime,
          cancellation: cancellation,
        );
        Object? parsed;
        try {
          parsed = jsonDecode(result);
        } on FormatException {
          parsed = result;
        }
        responseParts.add({
          'functionResponse': {
            'name': name,
            'response': parsed is Map ? parsed : {'result': parsed},
          },
        });
      }
      contents.add({'role': 'user', 'parts': responseParts});
    }

    final text = accumulatedText.trim();
    if (text.isEmpty) {
      throw const ApiException('The model returned an empty response.');
    }
    return ProviderChatResult(
      text: text,
      reasoning: reasoningParts.join('\n\n'),
      citations: allCitations,
      usedWebSearch: usedWebSearch,
    );
  }

  String _modelPath(String model) {
    final id = model.startsWith('models/') ? model.substring(7) : model;
    return Uri.encodeComponent(id);
  }

  bool _isParameterError(String message) {
    final lower = message.toLowerCase();
    return lower.contains('thinking') ||
        lower.contains('generationconfig') ||
        lower.contains('unsupported parameter') ||
        lower.contains('invalid argument');
  }

  List<Map<String, dynamic>> _buildContents(List<ChatMessage> messages) {
    final contents = <Map<String, dynamic>>[];
    for (final message in messages) {
      if (message.role == ChatRole.assistant) {
        if (message.text.trim().isNotEmpty) {
          contents.add({
            'role': 'model',
            'parts': [
              {'text': message.text},
            ],
          });
        }
        continue;
      }
      final parts = <Map<String, dynamic>>[];
      if (message.text.trim().isNotEmpty) {
        parts.add({'text': message.text});
      }
      for (final attachment in message.attachments) {
        if (attachment.kind == AttachmentKind.video ||
            attachment.kind == AttachmentKind.image ||
            guessedMimeType(attachment) == 'application/pdf') {
          parts.add({
            'inlineData': {
              'mimeType': guessedMimeType(attachment),
              'data': base64Encode(readAttachment(attachment)),
            },
          });
        } else if (isTextAttachment(attachment)) {
          parts.add({
            'text':
                'File: ${attachment.name}\n\n${readTextAttachment(attachment)}',
          });
        } else {
          parts.add({
            'text':
                '[The user attached ${attachment.name}, which this provider cannot read directly.]',
          });
        }
      }
      if (parts.isEmpty) {
        parts.add({'text': '(Empty message)'});
      }
      contents.add({'role': 'user', 'parts': parts});
    }
    return contents;
  }

  List<Map<String, dynamic>> _functionDeclarations(ChatToolRuntime runtime) {
    final declarations = <Map<String, dynamic>>[];
    if (runtime.hasImageTool) {
      declarations.add({
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
      });
    }
    if (runtime.hasVideoTool) {
      declarations.add({
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
      });
    }
    return declarations;
  }

  Future<String> _executeTool({
    required String name,
    required Object? arguments,
    required ChatToolRuntime runtime,
    CancellationToken? cancellation,
  }) async {
    try {
      cancellation?.throwIfCancelled();
      Map<String, dynamic> args = const {};
      if (arguments is Map) {
        args = arguments.map((key, value) => MapEntry('$key', value));
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
    cancellation?.throwIfCancelled();
    if (model.toLowerCase().contains('imagen')) {
      return _generateImagenImage(
        apiKey: apiKey,
        model: model,
        prompt: prompt,
        aspectRatio: aspectRatio,
        resolution: resolution,
        cancellation: cancellation,
      );
    }
    final json = await _createInteraction(
      apiKey: apiKey,
      body: {
        'model': model,
        'input': [
          {'type': 'text', 'text': prompt},
        ],
        'response_format': {
          'type': 'image',
          'mime_type': 'image/png',
          'aspect_ratio': _safeAspect(aspectRatio, const [
            '1:1',
            '16:9',
            '9:16',
            '4:3',
            '3:4',
          ]),
          'image_size': resolution.apiValue,
        },
      },
      timeout: const Duration(minutes: 6),
      cancellation: cancellation,
    );
    final media = await _extractMedia(json, const ['image']);
    return GeneratedMedia(
      bytes: media.bytes,
      mimeType: media.mimeType,
      extension: _extensionForMime(media.mimeType, fallback: 'png'),
    );
  }

  Future<GeneratedMedia> _generateImagenImage({
    required String apiKey,
    required String model,
    required String prompt,
    required String aspectRatio,
    ImageResolution resolution = ImageResolution.oneK,
    CancellationToken? cancellation,
  }) async {
    final parameters = <String, dynamic>{
      'sampleCount': 1,
      'aspectRatio': _safeAspect(aspectRatio, const [
        '1:1',
        '16:9',
        '9:16',
        '4:3',
        '3:4',
      ]),
    };
    // Imagen only accepts sampleImageSize on newer models; send it when the
    // user picked something above the default so older models stay unchanged.
    if (resolution != ImageResolution.oneK) {
      parameters['sampleImageSize'] = resolution.apiValue;
    }
    final json = await requestJson(
      _client,
      'POST',
      Uri.parse('$_baseUrl/models/${_modelPath(model)}:predict'),
      headers: _headers(apiKey),
      body: {
        'instances': [
          {'prompt': prompt},
        ],
        'parameters': parameters,
      },
      timeout: const Duration(minutes: 6),
    );
    cancellation?.throwIfCancelled();
    final predictions = json['predictions'];
    if (predictions is! List ||
        predictions.isEmpty ||
        predictions.first is! Map) {
      throw ApiException(
        extractErrorMessage(json) ?? 'Google returned no image.',
      );
    }
    final first = predictions.first as Map;
    final data = first['bytesBase64Encoded'];
    if (data is! String || data.isEmpty) {
      throw ApiException(
        first['raiFilteredReason']?.toString() ??
            'Google returned no image data.',
      );
    }
    final mime = first['mimeType']?.toString() ?? 'image/png';
    return GeneratedMedia(
      bytes: base64Decode(data),
      mimeType: mime,
      extension: _extensionForMime(mime, fallback: 'png'),
    );
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
    cancellation?.throwIfCancelled();
    if (model.toLowerCase().contains('veo')) {
      return _generateVeoVideo(
        apiKey: apiKey,
        model: model,
        prompt: prompt,
        aspectRatio: aspectRatio,
        seconds: seconds,
        cancellation: cancellation,
      );
    }
    final safeSeconds = seconds.clamp(3, 15);
    final json = await _createInteraction(
      apiKey: apiKey,
      body: {
        'model': model,
        'input': [
          {'type': 'text', 'text': prompt},
        ],
        'response_format': {
          'type': 'video',
          'delivery': 'uri',
          'aspect_ratio': _safeAspect(aspectRatio, const ['16:9', '9:16']),
          'resolution': '720p',
          'duration': '${safeSeconds}s',
        },
      },
      timeout: const Duration(minutes: 12),
      cancellation: cancellation,
    );
    cancellation?.throwIfCancelled();
    final media = _findMediaBlock(json, const ['video']);
    if (media == null) {
      throw const ApiException('Google returned no generated video.');
    }
    final mime =
        media['mime_type']?.toString() ??
        media['mimeType']?.toString() ??
        'video/mp4';

    final inline = media['data'];
    if (inline is String && inline.isNotEmpty) {
      return GeneratedMedia(
        bytes: base64Decode(inline),
        mimeType: mime,
        extension: _extensionForMime(mime, fallback: 'mp4'),
      );
    }

    final uri = media['uri']?.toString();
    if (uri == null || uri.isEmpty) {
      throw const ApiException('Google returned no generated video.');
    }
    final fileId = _fileIdFromUri(uri);
    if (fileId != null) {
      await _waitForFile(apiKey, fileId);
    }
    final request = http.Request('GET', Uri.parse(uri));
    final response = await rawRequest(
      _client,
      request,
      timeout: const Duration(minutes: 5),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        'Could not download the generated video (HTTP ${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
    final contentType = response.headers['content-type'] ?? '';
    final resolvedMime =
        contentType.startsWith('video/') || contentType.startsWith('image/')
        ? contentType.split(';').first
        : mime;
    return GeneratedMedia(
      bytes: Uint8List.fromList(response.bodyBytes),
      mimeType: resolvedMime,
      extension: _extensionForMime(resolvedMime, fallback: 'mp4'),
    );
  }

  Future<GeneratedMedia> _generateVeoVideo({
    required String apiKey,
    required String model,
    required String prompt,
    required String aspectRatio,
    required int seconds,
    CancellationToken? cancellation,
  }) async {
    final duration = seconds >= 8
        ? '8'
        : seconds >= 6
        ? '6'
        : '4';
    final started = await requestJson(
      _client,
      'POST',
      Uri.parse('$_baseUrl/models/${_modelPath(model)}:predictLongRunning'),
      headers: _headers(apiKey),
      body: {
        'instances': [
          {'prompt': prompt},
        ],
        'parameters': {
          'aspectRatio': _safeAspect(aspectRatio, const ['16:9', '9:16']),
          'durationSeconds': duration,
          'resolution': '720p',
          'personGeneration': 'allow_all',
        },
      },
      timeout: const Duration(minutes: 2),
    );
    cancellation?.throwIfCancelled();
    final operationName = started['name']?.toString();
    if (operationName == null || operationName.isEmpty) {
      throw ApiException(
        extractErrorMessage(started) ??
            'Google did not start the video generation.',
      );
    }

    final operation = await _waitForOperation(
      apiKey,
      operationName,
      cancellation: cancellation,
    );
    cancellation?.throwIfCancelled();
    final uri = _veoVideoUri(operation);
    if (uri == null || uri.isEmpty) {
      throw const ApiException('Google returned no generated video.');
    }
    final fileId = _fileIdFromUri(uri);
    if (fileId != null) {
      await _waitForFile(apiKey, fileId, cancellation: cancellation);
    }
    cancellation?.throwIfCancelled();

    final request = http.Request('GET', Uri.parse(uri));
    request.headers.addAll(_headers(apiKey));
    final response = await rawRequest(
      _client,
      request,
      timeout: const Duration(minutes: 5),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        'Could not download the generated video (HTTP ${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
    final contentType = response.headers['content-type'] ?? '';
    final mime = contentType.startsWith('video/')
        ? contentType.split(';').first
        : 'video/mp4';
    return GeneratedMedia(
      bytes: Uint8List.fromList(response.bodyBytes),
      mimeType: mime,
      extension: _extensionForMime(mime, fallback: 'mp4'),
    );
  }

  Future<Map<String, dynamic>> _waitForOperation(
    String apiKey,
    String operationName, {
    CancellationToken? cancellation,
  }) async {
    final parsed = Uri.tryParse(operationName);
    final uri = parsed != null && parsed.hasScheme
        ? parsed
        : Uri.parse('$_baseUrl/$operationName');
    final deadline = DateTime.now().add(const Duration(minutes: 12));
    while (DateTime.now().isBefore(deadline)) {
      cancellation?.throwIfCancelled();
      final json = await requestJson(
        _client,
        'GET',
        uri,
        headers: _headers(apiKey),
        timeout: const Duration(seconds: 60),
      );
      cancellation?.throwIfCancelled();
      if (json['error'] != null) {
        throw ApiException(
          extractErrorMessage(json) ?? 'Google video generation failed.',
        );
      }
      if (json['done'] == true) return json;
      await Future<void>.delayed(const Duration(seconds: 10));
    }
    throw const ApiException('Timed out while waiting for the video.');
  }

  String? _veoVideoUri(Map<String, dynamic> operation) {
    final response = operation['response'];
    if (response is! Map) return null;
    final containers = <Object?>[
      if (response['generateVideoResponse'] is Map) ...[
        (response['generateVideoResponse'] as Map)['generatedSamples'],
        (response['generateVideoResponse'] as Map)['generatedVideos'],
      ],
      response['generatedSamples'],
      response['generatedVideos'],
    ];
    for (final container in containers) {
      if (container is! List) continue;
      for (final sample in container) {
        if (sample is! Map) continue;
        final video = sample['video'];
        if (video is! Map) continue;
        final uri = video['uri'];
        if (uri is String && uri.isNotEmpty) return uri;
      }
    }
    return null;
  }

  String? _fileIdFromUri(String uri) {
    final parsed = Uri.tryParse(uri);
    final segments = parsed?.pathSegments ?? const <String>[];
    final index = segments.indexOf('files');
    if (index < 0 || index + 1 >= segments.length) return null;
    final id = segments[index + 1].split(':').first;
    return id.isEmpty ? null : id;
  }

  Future<void> _waitForFile(
    String apiKey,
    String fileId, {
    CancellationToken? cancellation,
  }) async {
    final deadline = DateTime.now().add(const Duration(minutes: 15));
    while (DateTime.now().isBefore(deadline)) {
      cancellation?.throwIfCancelled();
      final json = await requestJson(
        _client,
        'GET',
        Uri.parse('$_baseUrl/files/$fileId'),
        headers: _headers(apiKey),
        timeout: const Duration(seconds: 60),
      );
      cancellation?.throwIfCancelled();
      final state = json['state']?.toString();
      if (state == 'ACTIVE') return;
      if (state == 'FAILED') {
        throw ApiException(
          extractErrorMessage(json) ?? 'Google video processing failed.',
        );
      }
      await Future<void>.delayed(const Duration(seconds: 5));
    }
    throw const ApiException('Timed out while waiting for the video.');
  }

  Future<Map<String, dynamic>> _createInteraction({
    required String apiKey,
    required Map<String, dynamic> body,
    required Duration timeout,
    CancellationToken? cancellation,
  }) async {
    var response = await requestJson(
      _client,
      'POST',
      Uri.parse('$_baseUrl/interactions'),
      headers: {..._headers(apiKey), 'Api-Revision': '2026-05-20'},
      body: body,
      timeout: timeout,
    );
    cancellation?.throwIfCancelled();
    final id = response['id']?.toString();
    final status = response['status']?.toString();
    if (id != null &&
        id.isNotEmpty &&
        status != null &&
        status != 'completed' &&
        status != 'failed') {
      final deadline = DateTime.now().add(const Duration(minutes: 15));
      while (DateTime.now().isBefore(deadline)) {
        cancellation?.throwIfCancelled();
        await Future<void>.delayed(const Duration(seconds: 5));
        cancellation?.throwIfCancelled();
        response = await requestJson(
          _client,
          'GET',
          Uri.parse('$_baseUrl/interactions/$id'),
          headers: {..._headers(apiKey), 'Api-Revision': '2026-05-20'},
          timeout: const Duration(seconds: 60),
        );
        cancellation?.throwIfCancelled();
        final current = response['status']?.toString();
        if (current == 'completed') break;
        if (current == 'failed') {
          throw ApiException(
            extractErrorMessage(response) ?? 'Google generation failed.',
          );
        }
      }
    }
    if (response['status'] == 'failed') {
      throw ApiException(
        extractErrorMessage(response) ?? 'Google generation failed.',
      );
    }
    return response;
  }

  Future<({Uint8List bytes, String mimeType})> _extractMedia(
    Map<String, dynamic> json,
    List<String> types,
  ) async {
    final media = _findMediaBlock(json, types);
    if (media == null) {
      throw const ApiException('Google returned no generated media.');
    }
    final mime =
        media['mime_type']?.toString() ??
        media['mimeType']?.toString() ??
        (types.contains('video') ? 'video/mp4' : 'image/png');
    final bytes = base64Decode(media['data'] as String);
    return (bytes: bytes, mimeType: mime);
  }

  Map<String, dynamic>? _findMediaBlock(
    Map<String, dynamic> json,
    List<String> types,
  ) {
    Map<String, dynamic>? found;
    void visit(Object? node) {
      if (found != null) return;
      if (node is List) {
        for (final item in node) {
          visit(item);
        }
        return;
      }
      if (node is! Map) return;
      final map = node.map((key, value) => MapEntry(key.toString(), value));
      final type = map['type']?.toString();
      if (type != null &&
          types.contains(type) &&
          ((map['data'] is String && (map['data'] as String).isNotEmpty) ||
              (map['uri'] is String && (map['uri'] as String).isNotEmpty))) {
        found = map;
        return;
      }
      for (final value in map.values) {
        visit(value);
      }
    }

    visit(json);
    return found;
  }

  String _extensionForMime(String mime, {required String fallback}) {
    return switch (mime.toLowerCase()) {
      'image/png' => 'png',
      'image/jpeg' || 'image/jpg' => 'jpg',
      'image/webp' => 'webp',
      'video/mp4' => 'mp4',
      'video/webm' => 'webm',
      _ => fallback,
    };
  }
}
