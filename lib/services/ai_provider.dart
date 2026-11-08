import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

import '../core/models.dart';
import 'http_utils.dart';

typedef ImageToolCallback = Future<String> Function(
  String prompt,
  String aspectRatio,
);
typedef VideoToolCallback = Future<String> Function(
  String prompt,
  String aspectRatio,
  int durationSeconds,
);

class CancellationException implements Exception {
  const CancellationException();

  @override
  String toString() => 'Generation stopped.';
}

class CancellationToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
  }

  void throwIfCancelled() {
    if (_cancelled) throw const CancellationException();
  }
}

class ChatToolRuntime {
  ChatToolRuntime({
    required this.reasoning,
    required this.search,
    required this.onActivity,
    this.generateImage,
    this.generateVideo,
  });

  final ReasoningLevel reasoning;
  final SearchMode search;
  final void Function(ToolActivity activity) onActivity;
  final ImageToolCallback? generateImage;
  final VideoToolCallback? generateVideo;

  bool get hasImageTool => generateImage != null;
  bool get hasVideoTool => generateVideo != null;
}

class ProviderChatResult {
  const ProviderChatResult({
    required this.text,
    this.reasoning = '',
    this.citations = const [],
    this.usedWebSearch = false,
  });

  final String text;
  final String reasoning;
  final List<ChatCitation> citations;
  final bool usedWebSearch;
}

class GeneratedMedia {
  const GeneratedMedia({
    required this.bytes,
    required this.mimeType,
    required this.extension,
  });

  final Uint8List bytes;
  final String mimeType;
  final String extension;
}

abstract class AiProvider {
  AiProviderType get type;

  Future<void> validateKey({required String apiKey});

  Future<List<ModelOption>> listModels({
    required String apiKey,
    required ModelCategory category,
  });

  Future<ProviderChatResult> chat({
    required String apiKey,
    required String model,
    required List<ChatMessage> messages,
    required ChatToolRuntime runtime,
    CancellationToken? cancellation,
  });

  Future<GeneratedMedia> generateImage({
    required String apiKey,
    required String model,
    required String prompt,
    required String aspectRatio,
    ImageResolution resolution = ImageResolution.oneK,
    CancellationToken? cancellation,
  });

  Future<GeneratedMedia> generateVideo({
    required String apiKey,
    required String model,
    required String prompt,
    required String aspectRatio,
    required int seconds,
    CancellationToken? cancellation,
  });
}

Uint8List readAttachment(ChatAttachment attachment) {
  final file = File(attachment.path);
  if (!file.existsSync()) {
    throw const ApiException('An attached file could not be found.');
  }
  return file.readAsBytesSync();
}

String attachmentDataUri(ChatAttachment attachment) {
  final bytes = readAttachment(attachment);
  final mime = attachment.mimeType.isEmpty
      ? 'application/octet-stream'
      : attachment.mimeType;
  return 'data:$mime;base64,${base64Encode(bytes)}';
}

String guessedMimeType(ChatAttachment attachment) {
  if (attachment.mimeType.isNotEmpty &&
      attachment.mimeType != 'application/octet-stream') {
    return attachment.mimeType;
  }
  return lookupMimeType(attachment.path) ??
      lookupMimeType(attachment.name) ??
      'application/octet-stream';
}

bool isTextAttachment(ChatAttachment attachment) {
  final mime = guessedMimeType(attachment);
  return mime.startsWith('text/') ||
      mime == 'application/json' ||
      mime == 'application/xml' ||
      mime == 'application/x-yaml' ||
      p.extension(attachment.name).toLowerCase() == '.md';
}

String readTextAttachment(ChatAttachment attachment, {int maxChars = 50000}) {
  final text = utf8.decode(readAttachment(attachment), allowMalformed: true);
  if (text.length <= maxChars) return text;
  return '${text.substring(0, maxChars)}\n\n[File truncated]';
}

String? imageDataUri(ChatAttachment attachment) {
  if (attachment.kind != AttachmentKind.image) return null;
  return attachmentDataUri(attachment);
}

String toolErrorResult(Object error) {
  final message = error is ApiException ? error.message : error.toString();
  return jsonEncode({'ok': false, 'error': message});
}

String toolSuccessResult(String description) {
  return jsonEncode({'ok': true, 'result': description});
}

/// Collects web citations from the response shapes used by the four providers.
List<ChatCitation> collectCitations(Object? payload) {
  final found = <String, ChatCitation>{};

  void addUrl(Object? urlValue, Object? titleValue) {
    if (urlValue is! String) return;
    final uri = Uri.tryParse(urlValue);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) return;
    final title = titleValue is String && titleValue.trim().isNotEmpty
        ? titleValue.trim()
        : uri.host;
    found.putIfAbsent(
      urlValue,
      () => ChatCitation(title: title, url: urlValue),
    );
  }

  void visit(Object? node, {bool inCitation = false}) {
    if (node is List) {
      for (final item in node) {
        visit(item, inCitation: inCitation);
      }
      return;
    }
    if (node is! Map) return;
    final map = node.map((key, value) => MapEntry(key.toString(), value));
    final type = map['type']?.toString().toLowerCase() ?? '';
    final isCitation =
        inCitation ||
        type.contains('citation') ||
        type.contains('web_search_result') ||
        type.contains('grounding');
    final hasWeb = map['web'] is Map;
    if (hasWeb) {
      final web = map['web'] as Map;
      addUrl(web['uri'] ?? web['url'], web['title']);
    }
    if (isCitation || type == 'url_citation') {
      addUrl(map['url'] ?? map['uri'], map['title'] ?? map['name']);
      final nested = map['url_citation'];
      if (nested is Map) {
        addUrl(nested['url'] ?? nested['uri'], nested['title']);
      }
    }
    for (final entry in map.entries) {
      if (entry.key == 'url' || entry.key == 'uri') continue;
      visit(entry.value, inCitation: isCitation);
    }
  }

  visit(payload);
  return found.values.toList(growable: false);
}

List<ChatCitation> mergeCitations(
  Iterable<ChatCitation> first,
  Iterable<ChatCitation> second,
) {
  final seen = <String>{};
  final result = <ChatCitation>[];
  for (final citation in [...first, ...second]) {
    if (citation.url.isEmpty || !seen.add(citation.url)) continue;
    result.add(citation);
  }
  return result;
}

String buildSystemPrompt(ChatToolRuntime runtime) {
  final buffer = StringBuffer(
    'You are FaceUpAgents, a precise and helpful assistant. '
    'Reply in the same language as the user. '
    'Use Markdown for structure when it improves readability. ',
  );
  if (runtime.hasImageTool || runtime.hasVideoTool) {
    buffer.write(
      'When the user asks to create visual media, use the available generation tool instead of claiming you cannot. '
      'If a media generation tool returns an error, do not call it again in the same reply; explain the error to the user clearly. ',
    );
  }
  if (runtime.search.isEnabled) {
    buffer.write(
      'Use the web search tool when current or verifiable information is needed and cite the sources you relied on. ',
    );
  }
  if (runtime.search == SearchMode.deep) {
    buffer.write(
      'Do a thorough multi-step investigation: verify facts across several sources, compare them and explain disagreements. ',
    );
  }
  return buffer.toString().trim();
}

String trimUserMessage(String text, {int maxTitleLength = 52}) {
  final singleLine = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (singleLine.length <= maxTitleLength) return singleLine;
  return '${singleLine.substring(0, maxTitleLength).trimRight()}...';
}
