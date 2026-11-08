import 'dart:convert';

import 'package:flutter/material.dart';

enum AiProviderType {
  openai('OpenAI', 'openai'),
  anthropic('Anthropic', 'anthropic'),
  google('Google', 'google'),
  polza('Polza.ai', 'polza');

  const AiProviderType(this.label, this.storageKey);

  final String label;
  final String storageKey;
}

const List<AiProviderType> allProviders = AiProviderType.values;

enum ModelCategory {
  text,
  image,
  video;

  String get storageKey => name;

  String get localizationKey => switch (this) {
    ModelCategory.text => 'categoryText',
    ModelCategory.image => 'categoryImage',
    ModelCategory.video => 'categoryVideo',
  };

  String get subtitleKey => switch (this) {
    ModelCategory.text => 'categoryTextSubtitle',
    ModelCategory.image => 'categoryImageSubtitle',
    ModelCategory.video => 'categoryVideoSubtitle',
  };

  IconData get icon => switch (this) {
    ModelCategory.text => Icons.chat_bubble_outline_rounded,
    ModelCategory.image => Icons.image_outlined,
    ModelCategory.video => Icons.videocam_outlined,
  };
}

enum AppThemeChoice { light, dark, system }

enum AppFontChoice { inter, system }

enum AppLanguage {
  english('en'),
  russian('ru'),
  spanish('es');

  const AppLanguage(this.code);

  final String code;

  static AppLanguage fromCode(String? code) {
    return AppLanguage.values.firstWhere(
      (value) => value.code == code,
      orElse: () => AppLanguage.english,
    );
  }

  Locale get locale => Locale(code);
}

enum SearchMode {
  off,
  web,
  deep;

  bool get isEnabled => this != SearchMode.off;
}

enum ImageResolution {
  oneK('1K', 'resolution1K'),
  twoK('2K', 'resolution2K'),
  fourK('4K', 'resolution4K');

  const ImageResolution(this.apiValue, this.localizationKey);

  final String apiValue;
  final String localizationKey;

  static ImageResolution fromStorage(String? raw) {
    return ImageResolution.values.firstWhere(
      (value) => value.apiValue == raw || value.name == raw,
      orElse: () => ImageResolution.oneK,
    );
  }
}

enum ReasoningLevel {
  off,
  standard,
  deep;

  ReasoningLevel get next => switch (this) {
    ReasoningLevel.off => ReasoningLevel.standard,
    ReasoningLevel.standard => ReasoningLevel.deep,
    ReasoningLevel.deep => ReasoningLevel.off,
  };

  String get localizationKey => switch (this) {
    ReasoningLevel.off => 'reasoningOff',
    ReasoningLevel.standard => 'reasoningStandard',
    ReasoningLevel.deep => 'reasoningDeep',
  };
}

enum AttachmentKind { image, video, file }

enum ChatRole { user, assistant }

enum ToolActivity {
  thinking,
  searching,
  reading,
  generatingImage,
  generatingVideo,
}

enum ChatToolEvent {
  webSearch,
  deepSearch,
  imageGenerated,
  videoGenerated;

  String get localizationKey => switch (this) {
    ChatToolEvent.webSearch => 'toolWebSearch',
    ChatToolEvent.deepSearch => 'toolDeepSearch',
    ChatToolEvent.imageGenerated => 'toolImageGenerated',
    ChatToolEvent.videoGenerated => 'toolVideoGenerated',
  };

  IconData get icon => switch (this) {
    ChatToolEvent.webSearch => Icons.public_rounded,
    ChatToolEvent.deepSearch => Icons.manage_search_rounded,
    ChatToolEvent.imageGenerated => Icons.image_outlined,
    ChatToolEvent.videoGenerated => Icons.videocam_outlined,
  };
}

@immutable
class ModelOption {
  const ModelOption({
    required this.provider,
    required this.category,
    required this.id,
    required this.name,
    this.description,
  });

  final AiProviderType provider;
  final ModelCategory category;
  final String id;
  final String name;
  final String? description;

  Map<String, dynamic> toJson() => {
    'provider': provider.name,
    'category': category.name,
    'id': id,
    'name': name,
    'description': description,
  };

  factory ModelOption.fromJson(Map<String, dynamic> json) {
    return ModelOption(
      provider: AiProviderType.values.firstWhere(
        (v) => v.name == json['provider'],
        orElse: () => AiProviderType.openai,
      ),
      category: ModelCategory.values.firstWhere(
        (v) => v.name == json['category'],
        orElse: () => ModelCategory.text,
      ),
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
    );
  }
}

@immutable
class ChatAttachment {
  const ChatAttachment({
    required this.kind,
    required this.path,
    required this.name,
    required this.mimeType,
    this.generated = false,
  });

  final AttachmentKind kind;
  final String path;
  final String name;
  final String mimeType;
  final bool generated;

  ChatAttachment copyWith({
    AttachmentKind? kind,
    String? path,
    String? name,
    String? mimeType,
    bool? generated,
  }) {
    return ChatAttachment(
      kind: kind ?? this.kind,
      path: path ?? this.path,
      name: name ?? this.name,
      mimeType: mimeType ?? this.mimeType,
      generated: generated ?? this.generated,
    );
  }

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'path': path,
    'name': name,
    'mime': mimeType,
    'generated': generated,
  };

  factory ChatAttachment.fromJson(Map<String, dynamic> json) {
    return ChatAttachment(
      kind: AttachmentKind.values.firstWhere(
        (v) => v.name == json['kind'],
        orElse: () => AttachmentKind.file,
      ),
      path: json['path'] as String? ?? '',
      name: json['name'] as String? ?? '',
      mimeType: json['mime'] as String? ?? 'application/octet-stream',
      generated: json['generated'] as bool? ?? false,
    );
  }
}

@immutable
class ChatCitation {
  const ChatCitation({required this.title, required this.url});

  final String title;
  final String url;

  Map<String, dynamic> toJson() => {'title': title, 'url': url};

  factory ChatCitation.fromJson(Map<String, dynamic> json) {
    return ChatCitation(
      title: json['title'] as String? ?? '',
      url: json['url'] as String? ?? '',
    );
  }
}

@immutable
class ChatToolFailure {
  const ChatToolFailure({required this.kind, required this.message});

  final AttachmentKind kind;
  final String message;

  Map<String, dynamic> toJson() => {'kind': kind.name, 'message': message};

  factory ChatToolFailure.fromJson(Map<String, dynamic> json) {
    return ChatToolFailure(
      kind: AttachmentKind.values.firstWhere(
        (value) => value.name == json['kind'],
        orElse: () => AttachmentKind.file,
      ),
      message: json['message'] as String? ?? '',
    );
  }
}

@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.chatId,
    required this.role,
    required this.text,
    required this.createdAt,
    this.attachments = const [],
    this.citations = const [],
    this.toolEvents = const [],
    this.toolFailures = const [],
    this.reasoning = '',
    this.isError = false,
    this.isPending = false,
  });

  final String id;
  final String chatId;
  final ChatRole role;
  final String text;
  final DateTime createdAt;
  final List<ChatAttachment> attachments;
  final List<ChatCitation> citations;
  final List<ChatToolEvent> toolEvents;
  final List<ChatToolFailure> toolFailures;
  final String reasoning;
  final bool isError;
  final bool isPending;

  Map<String, Object?> toDatabase() => {
    'id': id,
    'chat_id': chatId,
    'role': role.name,
    'text': text,
    'created_at': createdAt.millisecondsSinceEpoch,
    'pending': isPending ? 1 : 0,
    'meta': jsonEncode({
      'attachments': attachments.map((a) => a.toJson()).toList(),
      'citations': citations.map((c) => c.toJson()).toList(),
      'tools': toolEvents.map((e) => e.name).toList(),
      'toolFailures': toolFailures.map((e) => e.toJson()).toList(),
      'reasoning': reasoning,
      'isError': isError,
    }),
  };

  factory ChatMessage.fromDatabase(Map<String, Object?> row) {
    Map<String, dynamic> meta = const {};
    final rawMeta = row['meta'];
    if (rawMeta is String && rawMeta.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawMeta);
        if (decoded is Map<String, dynamic>) meta = decoded;
      } on FormatException {
        meta = const {};
      }
    }
    final attachments = <ChatAttachment>[];
    final rawAttachments = meta['attachments'];
    if (rawAttachments is List) {
      for (final item in rawAttachments) {
        if (item is Map<String, dynamic>) {
          attachments.add(ChatAttachment.fromJson(item));
        }
      }
    }
    final citations = <ChatCitation>[];
    final rawCitations = meta['citations'];
    if (rawCitations is List) {
      for (final item in rawCitations) {
        if (item is Map<String, dynamic>) {
          citations.add(ChatCitation.fromJson(item));
        }
      }
    }
    final tools = <ChatToolEvent>[];
    final rawTools = meta['tools'];
    if (rawTools is List) {
      for (final item in rawTools) {
        if (item is! String) continue;
        for (final value in ChatToolEvent.values) {
          if (value.name == item) {
            tools.add(value);
            break;
          }
        }
      }
    }
    final toolFailures = <ChatToolFailure>[];
    final rawFailures = meta['toolFailures'];
    if (rawFailures is List) {
      for (final item in rawFailures) {
        if (item is Map<String, dynamic>) {
          toolFailures.add(ChatToolFailure.fromJson(item));
        }
      }
    }
    return ChatMessage(
      id: row['id'] as String,
      chatId: row['chat_id'] as String,
      role: ChatRole.values.firstWhere(
        (value) => value.name == row['role'],
        orElse: () => ChatRole.assistant,
      ),
      text: row['text'] as String? ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row['created_at'] as int? ?? 0,
      ),
      attachments: attachments,
      citations: citations,
      toolEvents: tools,
      toolFailures: toolFailures,
      reasoning: meta['reasoning'] as String? ?? '',
      isError: meta['isError'] as bool? ?? false,
      isPending: (row['pending'] as int? ?? 0) == 1,
    );
  }
}

@immutable
class ChatThread {
  const ChatThread({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;

  ChatThread copyWith({String? title, DateTime? updatedAt}) {
    return ChatThread(
      id: id,
      title: title ?? this.title,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

@immutable
class MediaGenerationConfig {
  const MediaGenerationConfig({
    required this.provider,
    required this.apiKey,
    required this.model,
  });

  final AiProviderType provider;
  final String apiKey;
  final String model;
}

@immutable
class ConnectResult {
  const ConnectResult({
    required this.provider,
    required this.category,
    required this.models,
    required this.supported,
  });

  final AiProviderType provider;
  final ModelCategory category;
  final List<ModelOption> models;
  final bool supported;
}

class ToolSettings {
  const ToolSettings({
    this.reasoning = ReasoningLevel.standard,
    this.search = SearchMode.off,
    this.imageGeneration = false,
    this.videoGeneration = false,
  });

  final ReasoningLevel reasoning;
  final SearchMode search;
  final bool imageGeneration;
  final bool videoGeneration;

  ToolSettings copyWith({
    ReasoningLevel? reasoning,
    SearchMode? search,
    bool? imageGeneration,
    bool? videoGeneration,
  }) {
    return ToolSettings(
      reasoning: reasoning ?? this.reasoning,
      search: search ?? this.search,
      imageGeneration: imageGeneration ?? this.imageGeneration,
      videoGeneration: videoGeneration ?? this.videoGeneration,
    );
  }
}

@immutable
class ChatCompletion {
  const ChatCompletion({
    required this.text,
    this.reasoning = '',
    this.citations = const [],
    this.attachments = const [],
    this.toolEvents = const [],
    this.toolFailures = const [],
  });

  final String text;
  final String reasoning;
  final List<ChatCitation> citations;
  final List<ChatAttachment> attachments;
  final List<ChatToolEvent> toolEvents;
  final List<ChatToolFailure> toolFailures;

  ChatCompletion withActivity({
    List<ChatAttachment>? attachments,
    List<ChatToolEvent>? toolEvents,
    List<ChatToolFailure>? toolFailures,
  }) {
    return ChatCompletion(
      text: text,
      reasoning: reasoning,
      citations: citations,
      attachments: attachments ?? this.attachments,
      toolEvents: toolEvents ?? this.toolEvents,
      toolFailures: toolFailures ?? this.toolFailures,
    );
  }
}
