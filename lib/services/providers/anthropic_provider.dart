import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/models.dart';
import '../ai_provider.dart';
import '../http_utils.dart';

class AnthropicProvider extends AiProvider {
  AnthropicProvider({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? 'https://api.anthropic.com/v1';

  final http.Client _client;
  final String _baseUrl;

  static const _apiVersion = '2023-06-01';

  @override
  AiProviderType get type => AiProviderType.anthropic;

  Map<String, String> _headers(String apiKey) => {
    'x-api-key': apiKey,
    'anthropic-version': _apiVersion,
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
    if (category != ModelCategory.text) return const [];
    final json = await requestJson(
      _client,
      'GET',
      Uri.parse('$_baseUrl/models?limit=1000'),
      headers: _headers(apiKey),
      timeout: const Duration(seconds: 30),
    );
    final options = <ModelOption>[];
    final data = json['data'];
    if (data is List) {
      for (final item in data) {
        if (item is! Map) continue;
        final id = item['id']?.toString() ?? '';
        if (!id.startsWith('claude')) continue;
        options.add(
          ModelOption(
            provider: type,
            category: category,
            id: id,
            name: item['display_name']?.toString() ?? id,
            description: item['type']?.toString(),
          ),
        );
      }
    }
    if (options.isEmpty) {
      for (final id in const [
        'claude-opus-4-6',
        'claude-sonnet-4-6',
        'claude-haiku-4-5',
      ]) {
        options.add(
          ModelOption(
            provider: type,
            category: ModelCategory.text,
            id: id,
            name: id,
          ),
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
    final transcript = _buildMessages(messages);
    var usedWebSearch = false;
    var includeReasoning = runtime.reasoning != ReasoningLevel.off;
    var accumulatedText = '';

    for (var turn = 0; turn < 8; turn++) {
      cancellation?.throwIfCancelled();
      final budget = runtime.reasoning == ReasoningLevel.deep ? 8192 : 2048;
      final body = <String, dynamic>{
        'model': model,
        'system': buildSystemPrompt(runtime),
        'messages': transcript,
        'max_tokens': includeReasoning ? budget + 4096 : 4096,
      };
      if (tools.isNotEmpty) {
        body['tools'] = tools;
      }
      if (includeReasoning) {
        body['thinking'] = {'type': 'enabled', 'budget_tokens': budget};
      }

      Map<String, dynamic> response;
      while (true) {
        try {
          response = await requestJson(
            _client,
            'POST',
            Uri.parse('$_baseUrl/messages'),
            headers: _headers(apiKey),
            body: body,
            timeout: const Duration(minutes: 5),
          );
          cancellation?.throwIfCancelled();
          break;
        } on ApiException catch (error) {
          if (includeReasoning &&
              error.statusCode == 400 &&
              _isParameterError(error.message, 'thinking')) {
            includeReasoning = false;
            body.remove('thinking');
            body['max_tokens'] = 4096;
            continue;
          }
          rethrow;
        }
      }

      final content = response['content'];
      final blocks = <Map<String, dynamic>>[];
      final toolUses = <Map<String, dynamic>>[];
      final responseText = <String>[];
      if (content is List) {
        for (final item in content) {
          if (item is! Map) continue;
          final block = item.map((k, v) => MapEntry(k.toString(), v));
          blocks.add(block);
          final blockType = block['type']?.toString();
          if (blockType == 'text' && block['text'] is String) {
            responseText.add(block['text'] as String);
          } else if (blockType == 'thinking' && block['thinking'] is String) {
            final thought = (block['thinking'] as String).trim();
            if (thought.isNotEmpty && !reasoningParts.contains(thought)) {
              reasoningParts.add(thought);
            }
          } else if (blockType == 'server_tool_use') {
            usedWebSearch = true;
          } else if (blockType == 'web_search_tool_result') {
            usedWebSearch = true;
          } else if (blockType == 'tool_use') {
            toolUses.add(block);
          }
        }
      }
      if (responseText.isNotEmpty) {
        accumulatedText = responseText.join('\n').trim();
      }
      allCitations.addAll(collectCitations(response));
      if (allCitations.isNotEmpty) usedWebSearch = true;

      if (toolUses.isEmpty) break;

      transcript.add({'role': 'assistant', 'content': blocks});
      final results = <Map<String, dynamic>>[];
      for (final call in toolUses) {
        final id = call['id']?.toString() ?? '';
        final name = call['name']?.toString() ?? '';
        final result = await _executeTool(
          name: name,
          arguments: call['input'],
          runtime: runtime,
          cancellation: cancellation,
        );
        results.add({
          'type': 'tool_result',
          'tool_use_id': id,
          'content': result,
        });
      }
      transcript.add({'role': 'user', 'content': results});
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

  bool _isParameterError(String message, String name) {
    final lower = message.toLowerCase();
    return lower.contains(name) ||
        lower.contains('unsupported parameter') ||
        lower.contains('unexpected parameter');
  }

  List<Map<String, dynamic>> _buildMessages(List<ChatMessage> messages) {
    final result = <Map<String, dynamic>>[];
    for (final message in messages) {
      if (message.role == ChatRole.assistant) {
        if (message.text.trim().isNotEmpty) {
          result.add({
            'role': 'assistant',
            'content': [
              {'type': 'text', 'text': message.text},
            ],
          });
        }
        continue;
      }
      final content = <Map<String, dynamic>>[];
      for (final attachment in message.attachments) {
        if (attachment.kind == AttachmentKind.image) {
          content.add({
            'type': 'image',
            'source': {
              'type': 'base64',
              'media_type': guessedMimeType(attachment),
              'data': base64Encode(readAttachment(attachment)),
            },
          });
        } else if (guessedMimeType(attachment) == 'application/pdf') {
          content.add({
            'type': 'document',
            'source': {
              'type': 'base64',
              'media_type': 'application/pdf',
              'data': base64Encode(readAttachment(attachment)),
            },
            'title': attachment.name,
          });
        } else if (isTextAttachment(attachment)) {
          content.add({
            'type': 'text',
            'text':
                'File: ${attachment.name}\n\n${readTextAttachment(attachment)}',
          });
        } else {
          content.add({
            'type': 'text',
            'text':
                '[The user attached ${attachment.name}, which this provider cannot read directly.]',
          });
        }
      }
      if (message.text.trim().isNotEmpty) {
        content.add({'type': 'text', 'text': message.text});
      }
      if (content.isEmpty) {
        content.add({'type': 'text', 'text': '(Empty message)'});
      }
      result.add({'role': 'user', 'content': content});
    }
    return result;
  }

  List<dynamic> _toolDefinitions(ChatToolRuntime runtime) {
    final tools = <dynamic>[];
    if (runtime.hasImageTool) {
      tools.add({
        'name': 'generate_image',
        'description': 'Generate an image from a detailed text prompt. Use this when the user asks for a new image, illustration, photo or visual.',
        'input_schema': {
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
      tools.add({
        'name': 'generate_video',
        'description': 'Generate a short video from a detailed text prompt. Use this only when the user asks for a video.',
        'input_schema': {
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
    if (runtime.search.isEnabled) {
      tools.add({
        'type': 'web_search_20250305',
        'name': 'web_search',
        'max_uses': runtime.search == SearchMode.deep ? 10 : 5,
      });
    }
    return tools;
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
    throw const ApiException(
      'Anthropic does not provide image generation. Connect an image model from OpenAI, Google or Polza.ai.',
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
    throw const ApiException(
      'Anthropic does not provide video generation. Connect a video model from OpenAI, Google or Polza.ai.',
    );
  }
}
