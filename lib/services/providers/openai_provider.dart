import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../core/models.dart';
import '../ai_provider.dart';
import '../http_utils.dart';

class OpenAiProvider extends AiProvider {
  OpenAiProvider({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? 'https://api.openai.com/v1';

  final http.Client _client;
  final String _baseUrl;

  @override
  AiProviderType get type => AiProviderType.openai;

  Map<String, String> _headers(String apiKey) => {
    'Authorization': 'Bearer $apiKey',
    'Content-Type': 'application/json',
  };

  @override
  Future<void> validateKey({required String apiKey}) async {
    await requestJson(
      _client,
      'GET',
      Uri.parse('$_baseUrl/models?limit=1'),
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
      Uri.parse('$_baseUrl/models'),
      headers: _headers(apiKey),
      timeout: const Duration(seconds: 30),
    );
    final entries = <Map<String, dynamic>>[];
    final rawData = json['data'];
    if (rawData is List) {
      for (final item in rawData) {
        if (item is Map<String, dynamic>) entries.add(item);
      }
    }
    entries.sort((a, b) {
      final aCreated = (a['created'] as num?)?.toInt() ?? 0;
      final bCreated = (b['created'] as num?)?.toInt() ?? 0;
      return bCreated.compareTo(aCreated);
    });

    final options = <ModelOption>[];
    for (final entry in entries) {
      final id = entry['id'] as String?;
      if (id == null || id.isEmpty) continue;
      final lower = id.toLowerCase();
      final matches = switch (category) {
        ModelCategory.text =>
          (lower.startsWith('gpt-') ||
                  lower.startsWith('chatgpt-') ||
                  RegExp(r'^o[0-9]').hasMatch(lower)) &&
              !lower.contains('image') &&
              !lower.contains('audio') &&
              !lower.contains('realtime') &&
              !lower.contains('transcribe') &&
              !lower.contains('tts') &&
              !lower.contains('whisper') &&
              !lower.contains('moderation') &&
              !lower.contains('embedding') &&
              !lower.contains('dall-e') &&
              !lower.contains('sora'),
        ModelCategory.image =>
          lower.contains('image') && !lower.contains('dall-e'),
        ModelCategory.video =>
          lower.contains('sora') || lower.contains('video'),
      };
      if (!matches) continue;
      options.add(
        ModelOption(
          provider: type,
          category: category,
          id: id,
          name: id,
          description: entry['owned_by'] as String?,
        ),
      );
    }

    if (options.isEmpty) {
      final fallback = switch (category) {
        ModelCategory.text => const <String>[],
        ModelCategory.image => const <String>[
          'gpt-image-2.6-flare',
          'gpt-image-2.6-sunburst',
          'gpt-image-2.5-flare',
          'gpt-image-2.5-sunburst',
          'gpt-image-2',
          'gpt-image-1.5',
          'gpt-image-1-mini',
          'chatgpt-image-latest',
        ],
        ModelCategory.video => const <String>['sora-2', 'sora-2-pro'],
      };
      for (final id in fallback) {
        options.add(
          ModelOption(provider: type, category: category, id: id, name: id),
        );
      }
    }
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
    final allCitations = <ChatCitation>[];
    final reasoningParts = <String>[];
    var usedWebSearch = false;
    var includeReasoning = runtime.reasoning != ReasoningLevel.off;
    var currentInput = _buildInput(messages);
    String? previousResponseId;
    var finalText = '';
    var accumulatedText = '';

    for (var turn = 0; turn < 8; turn++) {
      cancellation?.throwIfCancelled();
      final body = <String, dynamic>{
        'model': model,
        'input': currentInput,
        'store': true,
      };
      if (previousResponseId == null) {
        body['instructions'] = buildSystemPrompt(runtime);
      } else {
        body['previous_response_id'] = previousResponseId;
      }
      if (tools.isNotEmpty) {
        body['tools'] = tools;
        body['tool_choice'] = 'auto';
      }
      if (includeReasoning) {
        body['reasoning'] = {
          'effort': runtime.reasoning == ReasoningLevel.deep
              ? 'high'
              : 'medium',
          'summary': 'auto',
        };
      }

      Map<String, dynamic> response;
      while (true) {
        try {
          response = await requestJson(
            _client,
            'POST',
            Uri.parse('$_baseUrl/responses'),
            headers: _headers(apiKey),
            body: body,
            timeout: const Duration(minutes: 5),
          );
          cancellation?.throwIfCancelled();
          break;
        } on ApiException catch (error) {
          if (includeReasoning &&
              error.statusCode == 400 &&
              _isReasoningError(error.message)) {
            includeReasoning = false;
            body.remove('reasoning');
            continue;
          }
          rethrow;
        }
      }

      final apiError = response['error'];
      if (apiError != null) {
        throw ApiException(extractErrorMessage(response) ?? 'OpenAI error.');
      }

      final output = response['output'];
      final functionCalls = <Map<String, dynamic>>[];
      if (output is List) {
        for (final item in output) {
          if (item is! Map) continue;
          final map = item.map((k, v) => MapEntry(k.toString(), v));
          final itemType = map['type']?.toString();
          if (itemType == 'web_search_call') usedWebSearch = true;
          if (itemType == 'function_call') {
            functionCalls.add(map.cast<String, dynamic>());
          }
          if (itemType == 'reasoning') {
            final summary = map['summary'];
            if (summary is List) {
              for (final part in summary) {
                if (part is Map && part['text'] is String) {
                  final text = (part['text'] as String).trim();
                  if (text.isNotEmpty && !reasoningParts.contains(text)) {
                    reasoningParts.add(text);
                  }
                }
              }
            }
          }
          if (itemType == 'message') {
            final content = map['content'];
            if (content is List) {
              for (final part in content) {
                if (part is! Map) continue;
                final partType = part['type']?.toString();
                if (partType == 'output_text' && part['text'] is String) {
                  accumulatedText += part['text'] as String;
                } else if (partType == 'refusal' && part['refusal'] is String) {
                  accumulatedText += part['refusal'] as String;
                }
              }
            }
          }
        }
      }
      final topLevelText = response['output_text'];
      if (topLevelText is String && topLevelText.isNotEmpty) {
        accumulatedText += topLevelText;
      }
      allCitations.addAll(collectCitations(response));
      if (allCitations.isNotEmpty) usedWebSearch = true;

      if (functionCalls.isEmpty) {
        finalText = accumulatedText.trim();
        previousResponseId = response['id'] as String?;
        break;
      }

      final toolOutputs = <Map<String, dynamic>>[];
      for (final call in functionCalls) {
        final callId = call['call_id'] as String? ?? '';
        final name = call['name'] as String? ?? '';
        final arguments = call['arguments'];
        final result = await _executeTool(
          name: name,
          rawArguments: arguments,
          runtime: runtime,
          cancellation: cancellation,
        );
        toolOutputs.add({
          'type': 'function_call_output',
          'call_id': callId,
          'output': result,
        });
      }
      previousResponseId = response['id'] as String?;
      if (previousResponseId == null) {
        throw const ApiException(
          'OpenAI did not return a response id for the tool loop.',
        );
      }
      currentInput = toolOutputs;
    }

    if (finalText.isEmpty) {
      finalText = accumulatedText.trim();
    }
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

  bool _isReasoningError(String message) {
    final lower = message.toLowerCase();
    return lower.contains('reasoning') ||
        lower.contains('effort') ||
        lower.contains('summary') ||
        lower.contains('unsupported parameter');
  }

  List<dynamic> _buildInput(List<ChatMessage> messages) {
    final input = <dynamic>[];
    for (final message in messages) {
      if (message.role == ChatRole.assistant) {
        if (message.text.trim().isNotEmpty) {
          input.add({'role': 'assistant', 'content': message.text});
        }
        continue;
      }
      final parts = <Map<String, dynamic>>[];
      if (message.text.trim().isNotEmpty) {
        parts.add({'type': 'input_text', 'text': message.text});
      }
      for (final attachment in message.attachments) {
        if (attachment.kind == AttachmentKind.image) {
          parts.add({
            'type': 'input_image',
            'image_url': attachmentDataUri(attachment),
            'detail': 'auto',
          });
        } else if (isTextAttachment(attachment)) {
          parts.add({
            'type': 'input_text',
            'text':
                'File: ${attachment.name}\n\n${readTextAttachment(attachment)}',
          });
        } else if (attachment.kind == AttachmentKind.video) {
          parts.add({
            'type': 'input_text',
            'text':
                '[The user attached a video (${attachment.name}). This provider cannot read local video input, so it was not sent.]',
          });
        } else {
          parts.add({
            'type': 'input_file',
            'filename': attachment.name,
            'file_data': attachmentDataUri(attachment),
          });
        }
      }
      if (parts.isEmpty) {
        parts.add({'type': 'input_text', 'text': '(Empty message)'});
      }
      input.add({'role': 'user', 'content': parts});
    }
    return input;
  }

  List<dynamic> _toolDefinitions(ChatToolRuntime runtime) {
    final tools = <dynamic>[];
    if (runtime.hasImageTool) {
      tools.add({
        'type': 'function',
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
          'additionalProperties': false,
        },
        'strict': false,
      });
    }
    if (runtime.hasVideoTool) {
      tools.add({
        'type': 'function',
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
          'additionalProperties': false,
        },
        'strict': false,
      });
    }
    if (runtime.search.isEnabled) {
      tools.add({
        'type': 'web_search',
        'search_context_size': runtime.search == SearchMode.deep
            ? 'high'
            : 'medium',
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
          final result = await callback(prompt, aspect);
          return toolSuccessResult(result);
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
          final result = await callback(prompt, aspect, duration);
          return toolSuccessResult(result);
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
    final base = switch (resolution) {
      ImageResolution.oneK => 1024,
      ImageResolution.twoK => 2048,
      ImageResolution.fourK => 4096,
    };
    final size = switch (aspectRatio) {
      '16:9' || '4:3' => '${(base * 1.5).round()}x$base',
      '9:16' || '3:4' => '${base}x${(base * 1.5).round()}',
      _ => '${base}x$base',
    };
    cancellation?.throwIfCancelled();
    final json = await requestJson(
      _client,
      'POST',
      Uri.parse('$_baseUrl/images/generations'),
      headers: _headers(apiKey),
      body: {'model': model, 'prompt': prompt, 'size': size, 'n': 1},
      timeout: const Duration(minutes: 5),
    );
    cancellation?.throwIfCancelled();
    final data = json['data'];
    if (data is! List || data.isEmpty || data.first is! Map) {
      throw ApiException(
        extractErrorMessage(json) ?? 'OpenAI returned no image.',
      );
    }
    final first = data.first as Map;
    final b64 = first['b64_json'];
    if (b64 is String && b64.isNotEmpty) {
      return GeneratedMedia(
        bytes: base64Decode(b64),
        mimeType: 'image/png',
        extension: 'png',
      );
    }
    final url = first['url'];
    if (url is String && url.isNotEmpty) {
      final bytes = await _download(url);
      return GeneratedMedia(
        bytes: bytes,
        mimeType: 'image/png',
        extension: 'png',
      );
    }
    throw const ApiException('OpenAI returned no image data.');
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
    final safeSeconds = switch (seconds) {
      <= 4 => 4,
      <= 8 => 8,
      _ => 12,
    };
    final size = switch (aspectRatio) {
      '9:16' => '720x1280',
      '1:1' => '1024x1024',
      _ => '1280x720',
    };
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl/videos'),
    );
    request.headers['Authorization'] = 'Bearer $apiKey';
    request.fields.addAll({
      'model': model,
      'prompt': prompt,
      'seconds': '$safeSeconds',
      'size': size,
    });
    final createResponse = await rawRequest(
      _client,
      request,
      timeout: const Duration(minutes: 3),
    );
    cancellation?.throwIfCancelled();
    var status = decodeResponse(createResponse);
    final videoId = status['id'] as String?;
    if (videoId == null || videoId.isEmpty) {
      throw const ApiException('OpenAI returned no video job id.');
    }
    final deadline = DateTime.now().add(const Duration(minutes: 20));
    while (DateTime.now().isBefore(deadline)) {
      final state = status['status'] as String? ?? '';
      if (state == 'completed') {
        final contentRequest = http.Request(
          'GET',
          Uri.parse('$_baseUrl/videos/$videoId/content'),
        );
        contentRequest.headers['Authorization'] = 'Bearer $apiKey';
        final content = await rawRequest(
          _client,
          contentRequest,
          timeout: const Duration(minutes: 3),
        );
        if (content.statusCode < 200 || content.statusCode >= 300) {
          String? message;
          try {
            final decoded = jsonDecode(utf8.decode(content.bodyBytes));
            if (decoded is Map<String, dynamic>) {
              message = extractErrorMessage(decoded);
            }
          } on FormatException {
            message = null;
          }
          throw ApiException(
            message ?? 'Could not download the generated video.',
            statusCode: content.statusCode,
          );
        }
        return GeneratedMedia(
          bytes: Uint8List.fromList(content.bodyBytes),
          mimeType: content.headers['content-type'] ?? 'video/mp4',
          extension: 'mp4',
        );
      }
      if (state == 'failed') {
        final error = status['error'];
        final message = error is Map
            ? error['message']?.toString()
            : error?.toString();
        throw ApiException(message ?? 'OpenAI video generation failed.');
      }
      await Future<void>.delayed(const Duration(seconds: 5));
      cancellation?.throwIfCancelled();
      status = await requestJson(
        _client,
        'GET',
        Uri.parse('$_baseUrl/videos/$videoId'),
        headers: _headers(apiKey),
        timeout: const Duration(seconds: 60),
      );
      cancellation?.throwIfCancelled();
    }
    throw const ApiException('Timed out while waiting for the video.');
  }

  Future<Uint8List> _download(String url) async {
    final request = http.Request('GET', Uri.parse(url));
    final response = await rawRequest(
      _client,
      request,
      timeout: const Duration(minutes: 2),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        'Could not download the generated image (HTTP ${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
    return Uint8List.fromList(response.bodyBytes);
  }
}
