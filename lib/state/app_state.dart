import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../core/app_strings.dart';
import '../core/models.dart';
import '../data/chat_store.dart';
import '../data/settings_store.dart';
import '../services/ai_provider.dart';
import '../services/chat_service.dart';
import '../services/http_utils.dart';
import '../services/media_store.dart';
import '../services/provider_registry.dart';

class ChatGenerationJob {
  ChatGenerationJob({
    required this.chatId,
    required this.messageId,
    required this.thread,
    required this.createdAt,
  });

  final String chatId;
  final String messageId;
  final ChatThread thread;
  final DateTime createdAt;
  final CancellationToken cancellation = CancellationToken();
  final List<ChatAttachment> partialAttachments = [];
  final List<ChatToolEvent> toolEvents = [];
  bool cancelled = false;
  ToolActivity activity = ToolActivity.thinking;
}

class ApiRefreshResult {
  const ApiRefreshResult({required this.catalogs, required this.failures});

  /// Freshly fetched model lists per category.
  final Map<ModelCategory, List<ModelOption>> catalogs;

  /// Human readable errors for categories that could not be refreshed.
  final List<String> failures;

  bool get hasAnything => catalogs.isNotEmpty || failures.isNotEmpty;
}

class AppState extends ChangeNotifier {
  AppState({
    required this.settings,
    required this.database,
    required this.mediaStore,
    ProviderRegistry? providers,
    ChatService? chatService,
    Uuid? uuid,
  }) : providers = providers ?? ProviderRegistry(),
       _uuid = uuid ?? const Uuid() {
    _chatService =
        chatService ??
        ChatService(registry: this.providers, mediaStore: mediaStore);
  }

  final SettingsStore settings;
  final ChatStore database;
  final MediaStore mediaStore;
  final ProviderRegistry providers;
  final Uuid _uuid;
  late final ChatService _chatService;

  AppThemeChoice _theme = AppThemeChoice.system;
  AppFontChoice _font = AppFontChoice.inter;
  AppLanguage _language = AppLanguage.english;
  ImageResolution _imageResolution = ImageResolution.oneK;
  Map<AiProviderType, String> _keys = const {};
  final Map<ModelCategory, ModelOption> _models = {};
  final Map<String, ChatGenerationJob> _generationJobs = {};
  final Map<String, int> _messageVersions = {};
  final Set<String> _deletedChats = {};
  List<ChatThread> _chats = const [];
  bool _ready = false;

  AppThemeChoice get theme => _theme;
  AppFontChoice get font => _font;
  AppLanguage get language => _language;
  ImageResolution get imageResolution => _imageResolution;
  List<ChatThread> get chats => _chats;
  bool get ready => _ready;

  ThemeMode get themeMode => switch (_theme) {
    AppThemeChoice.light => ThemeMode.light,
    AppThemeChoice.dark => ThemeMode.dark,
    AppThemeChoice.system => ThemeMode.system,
  };

  bool get useInter => _font == AppFontChoice.inter;

  AppStrings get strings => AppStrings(_language);

  String t(String key) => strings.t(key);

  ChatGenerationJob? generationJobFor(String chatId) => _generationJobs[chatId];

  bool isGenerating(String chatId) => _generationJobs.containsKey(chatId);

  int messageVersion(String chatId) => _messageVersions[chatId] ?? 0;

  Future<void> init() async {
    _theme = settings.readTheme();
    _font = settings.readFont();
    _language = settings.readLanguage();
    _imageResolution = settings.readImageResolution();
    for (final category in ModelCategory.values) {
      final model = settings.readModel(category);
      if (model != null) _models[category] = model;
    }
    _keys = await settings.readKeys();
    _chats = await database.listChats();
    await _recoverInterruptedGenerations();
    _ready = true;
    notifyListeners();
  }

  Future<void> _recoverInterruptedGenerations() async {
    final pending = await database.pendingMessages();
    if (pending.isEmpty) return;
    for (final message in pending) {
      final hasMedia = message.attachments.isNotEmpty;
      final interrupted = ChatMessage(
        id: message.id,
        chatId: message.chatId,
        role: ChatRole.assistant,
        text: strings.t(
          hasMedia ? 'generationInterruptedWithMedia' : 'generationInterrupted',
        ),
        createdAt: message.createdAt,
        attachments: message.attachments,
        toolEvents: message.toolEvents,
        isError: true,
      );
      await database.insertMessage(interrupted);
    }
    _chats = await database.listChats();
  }

  Future<void> setTheme(AppThemeChoice value) async {
    if (_theme == value) return;
    _theme = value;
    notifyListeners();
    await settings.writeTheme(value);
  }

  Future<void> setFont(AppFontChoice value) async {
    if (_font == value) return;
    _font = value;
    notifyListeners();
    await settings.writeFont(value);
  }

  Future<void> setLanguage(AppLanguage value) async {
    if (_language == value) return;
    _language = value;
    notifyListeners();
    await settings.writeLanguage(value);
  }

  Future<void> setImageResolution(ImageResolution value) async {
    if (_imageResolution == value) return;
    _imageResolution = value;
    notifyListeners();
    await settings.writeImageResolution(value);
  }

  String? keyFor(AiProviderType provider) => _keys[provider];

  bool hasKey(AiProviderType provider) =>
      (_keys[provider] ?? '').trim().isNotEmpty;

  ModelOption? modelFor(ModelCategory category) => _models[category];

  bool get hasTextModel => _models[ModelCategory.text] != null;

  Future<ConnectResult> connectProvider({
    required AiProviderType provider,
    required ModelCategory category,
    required String apiKey,
  }) async {
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) {
      throw ApiException(strings.t('keyRequired'));
    }
    if (!providers.supports(provider, category)) {
      throw ApiException(strings.t('providerCategoryUnsupported'));
    }
    final adapter = providers.forType(provider);
    await adapter.validateKey(apiKey: trimmed);
    final models = await adapter.listModels(
      apiKey: trimmed,
      category: category,
    );
    await settings.writeKey(provider, trimmed);
    _keys = {..._keys, provider: trimmed};
    notifyListeners();
    return ConnectResult(
      provider: provider,
      category: category,
      models: models,
      supported: true,
    );
  }

  Future<void> selectModel(ModelOption model) async {
    _models[model.category] = model;
    notifyListeners();
    await settings.writeModel(model);
  }

  Future<void> clearModel(ModelCategory category) async {
    if (_models.remove(category) == null) return;
    notifyListeners();
    await settings.clearModel(category);
  }

  Future<void> clearProviderKey(AiProviderType provider) async {
    await settings.writeKey(provider, '');
    final clearedCategories = <ModelCategory>[];
    for (final category in ModelCategory.values) {
      if (_models[category]?.provider == provider) {
        _models.remove(category);
        clearedCategories.add(category);
      }
    }
    for (final category in clearedCategories) {
      await settings.clearModel(category);
    }
    _keys = {..._keys}..remove(provider);
    notifyListeners();
  }

  /// Re-fetches the model catalog for every connected category in one go.
  ///
  /// Uses the stored API keys, so no key has to be re-entered. If the
  /// currently selected model still exists, its metadata is refreshed and
  /// persisted; the selection itself is never silently dropped.
  Future<ApiRefreshResult> refreshApi({
    Map<ModelCategory, AiProviderType> providers = const {},
  }) async {
    final catalogs = <ModelCategory, List<ModelOption>>{};
    final failures = <String>[];
    final updated = <ModelCategory, ModelOption>{};

    for (final category in ModelCategory.values) {
      final provider = providers[category];
      if (provider == null || !this.providers.supports(provider, category)) {
        continue;
      }
      final apiKey = keyFor(provider);
      if (apiKey == null || apiKey.trim().isEmpty) continue;
      try {
        final models = await this.providers
            .forType(provider)
            .listModels(apiKey: apiKey, category: category);
        catalogs[category] = models;
        final current = _models[category];
        if (current != null && current.provider == provider) {
          ModelOption? match;
          for (final model in models) {
            if (model.id == current.id) {
              match = model;
              break;
            }
          }
          if (match != null) {
            _models[category] = match;
            updated[category] = match;
          }
        }
      } catch (error) {
        failures.add('${t(category.localizationKey)}: ${errorText(error)}');
      }
    }

    for (final entry in updated.entries) {
      await settings.writeModel(entry.value);
    }
    if (catalogs.isNotEmpty || updated.isNotEmpty) notifyListeners();
    return ApiRefreshResult(catalogs: catalogs, failures: failures);
  }

  Future<ChatThread> createChat() async {
    final now = DateTime.now();
    final thread = await database.createChat(_uuid.v4(), now);
    _chats = [thread, ..._chats];
    notifyListeners();
    return thread;
  }

  Future<void> refreshChats() async {
    _chats = await database.listChats();
    notifyListeners();
  }

  Future<void> renameChat(ChatThread thread, String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    final now = DateTime.now();
    await database.renameChat(thread.id, trimmed, now);
    _chats =
        _chats
            .map(
              (item) => item.id == thread.id
                  ? item.copyWith(title: trimmed, updatedAt: now)
                  : item,
            )
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    notifyListeners();
  }

  Future<void> deleteChat(ChatThread thread) async {
    final hadJob = _generationJobs.remove(thread.id) != null;
    if (hadJob) _deletedChats.add(thread.id);
    await database.deleteChat(thread.id);
    _chats = _chats.where((item) => item.id != thread.id).toList();
    _bumpMessages(thread.id);
    notifyListeners();
  }

  Future<void> touchChat(ChatThread thread) async {
    final now = DateTime.now();
    await database.touchChat(thread.id, now);
    _chats =
        _chats
            .map(
              (item) =>
                  item.id == thread.id ? item.copyWith(updatedAt: now) : item,
            )
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    notifyListeners();
  }

  Future<List<ChatMessage>> messagesFor(ChatThread thread) {
    return database.messagesForChat(thread.id);
  }

  Future<void> insertMessage(ChatMessage message) {
    return database.insertMessage(message);
  }

  Future<void> deleteMessage(String id) {
    return database.deleteMessage(id);
  }

  /// Runs one assistant turn outside the widget tree.
  ///
  /// The pending assistant message is written to the database immediately, so
  /// the chat survives navigation and can recover cleanly after a process
  /// restart. Callers should not await this to keep the UI responsive.
  Future<void> generateReply({
    required ChatThread thread,
    required List<ChatMessage> messages,
    required ToolSettings settings,
  }) async {
    if (_generationJobs.containsKey(thread.id)) return;

    final textModel = modelFor(ModelCategory.text);
    final apiKey = textModel == null ? null : keyFor(textModel.provider);
    if (textModel == null || apiKey == null) {
      throw ApiException(strings.t('configureTitle'));
    }
    final imageModel = settings.imageGeneration
        ? modelFor(ModelCategory.image)
        : null;
    final imageApiKey = imageModel == null ? null : keyFor(imageModel.provider);
    final videoModel = settings.videoGeneration
        ? modelFor(ModelCategory.video)
        : null;
    final videoApiKey = videoModel == null ? null : keyFor(videoModel.provider);

    final placeholder = createMessage(
      chatId: thread.id,
      role: ChatRole.assistant,
      text: '',
      isPending: true,
    );
    await database.insertMessage(placeholder);

    final job = ChatGenerationJob(
      chatId: thread.id,
      messageId: placeholder.id,
      thread: thread,
      createdAt: placeholder.createdAt,
    );
    _generationJobs[thread.id] = job;
    _bumpMessages(thread.id);
    notifyListeners();

    try {
      final completion = await _chatService.complete(
        messages: messages,
        textModel: textModel,
        apiKey: apiKey,
        settings: settings,
        cancellation: job.cancellation,
        onActivity: (activity) {
          if (job.cancelled) return;
          if (!identical(_generationJobs[thread.id], job)) return;
          if (job.activity == activity) return;
          job.activity = activity;
          notifyListeners();
        },
        onAttachment: (attachment) async {
          if (_deletedChats.contains(thread.id)) return;
          job.partialAttachments.add(attachment);
          if (job.cancelled) {
            // The user already stopped this turn; keep the freshly generated
            // file by folding it into the persisted "stopped" message.
            await _persistStopped(job);
            _bumpMessages(thread.id);
            notifyListeners();
            return;
          }
          await database.insertMessage(
            ChatMessage(
              id: placeholder.id,
              chatId: thread.id,
              role: ChatRole.assistant,
              text: '',
              createdAt: placeholder.createdAt,
              attachments: List.unmodifiable(job.partialAttachments),
              isPending: true,
            ),
          );
          if (_deletedChats.contains(thread.id)) return;
          if (job.cancelled) {
            await _persistStopped(job);
            _bumpMessages(thread.id);
            notifyListeners();
            return;
          }
          // Refresh any open chat so the saved media becomes visible while
          // the text model is still composing its reply.
          _bumpMessages(thread.id);
          notifyListeners();
        },
        imageModel: imageModel,
        imageApiKey: imageApiKey,
        videoModel: videoModel,
        videoApiKey: videoApiKey,
        imageResolution: _imageResolution,
      );

      if (_deletedChats.remove(thread.id)) return;
      if (job.cancelled) return;

      final hadText = completion.text.trim().isNotEmpty;
      final text = hadText
          ? completion.text.trim()
          : completion.attachments.isNotEmpty
          ? strings.t('generatedMediaFallback')
          : strings.t('generationFailed');
      final assistant = ChatMessage(
        id: placeholder.id,
        chatId: thread.id,
        role: ChatRole.assistant,
        text: text,
        createdAt: placeholder.createdAt,
        attachments: completion.attachments,
        citations: completion.citations,
        toolEvents: completion.toolEvents,
        toolFailures: completion.toolFailures,
        reasoning: completion.reasoning,
        isError:
            !hadText &&
            completion.attachments.isEmpty &&
            completion.toolFailures.isNotEmpty,
      );
      await database.insertMessage(assistant);
    } on CancellationException {
      // stopGeneration already persisted the stopped message.
      if (!job.cancelled) {
        await _persistStopped(job);
        _bumpMessages(thread.id);
        notifyListeners();
      }
    } catch (error) {
      if (_deletedChats.remove(thread.id)) return;
      if (job.cancelled) return;
      final failure = ChatMessage(
        id: placeholder.id,
        chatId: thread.id,
        role: ChatRole.assistant,
        text: errorText(error),
        createdAt: placeholder.createdAt,
        isError: true,
      );
      await database.insertMessage(failure);
    } finally {
      if (identical(_generationJobs[thread.id], job)) {
        _generationJobs.remove(thread.id);
        _bumpMessages(thread.id);
        notifyListeners();
      }
    }

    if (!job.cancelled && !_deletedChats.contains(thread.id)) {
      await touchChat(thread);
    }
  }

  /// Stops the running generation for a chat.
  ///
  /// The UI spinner stops immediately, already generated media is kept, and
  /// the pending placeholder becomes a persisted "stopped" message so late
  /// provider results cannot overwrite it.
  Future<void> stopGeneration(String chatId) async {
    final job = _generationJobs.remove(chatId);
    if (job == null) return;
    job.cancelled = true;
    job.cancellation.cancel();
    await _persistStopped(job);
    _bumpMessages(chatId);
    notifyListeners();
    await touchChat(job.thread);
  }

  Future<void> _persistStopped(ChatGenerationJob job) async {
    if (_deletedChats.contains(job.chatId)) return;
    final hasMedia = job.partialAttachments.isNotEmpty;
    final events = <ChatToolEvent>{};
    for (final attachment in job.partialAttachments) {
      events.add(
        attachment.kind == AttachmentKind.video
            ? ChatToolEvent.videoGenerated
            : ChatToolEvent.imageGenerated,
      );
    }
    await database.insertMessage(
      ChatMessage(
        id: job.messageId,
        chatId: job.chatId,
        role: ChatRole.assistant,
        text: strings.t(
          hasMedia ? 'generationStoppedWithMedia' : 'generationStopped',
        ),
        createdAt: job.createdAt,
        attachments: List.unmodifiable(job.partialAttachments),
        toolEvents: List.unmodifiable(events),
        isError: false,
      ),
    );
  }

  String errorText(Object error) {
    if (error is ApiException) {
      final lower = error.message.toLowerCase();
      if (lower.contains('took too long')) return strings.t('timeoutError');
      if (lower.contains('could not reach')) return strings.t('networkError');
      return error.message;
    }
    return '${strings.t('requestFailed')}: $error';
  }

  ChatMessage createMessage({
    required String chatId,
    required ChatRole role,
    required String text,
    List<ChatAttachment> attachments = const [],
    List<ChatCitation> citations = const [],
    List<ChatToolEvent> toolEvents = const [],
    List<ChatToolFailure> toolFailures = const [],
    String reasoning = '',
    bool isError = false,
    bool isPending = false,
  }) {
    return ChatMessage(
      id: _uuid.v4(),
      chatId: chatId,
      role: role,
      text: text,
      createdAt: DateTime.now(),
      attachments: attachments,
      citations: citations,
      toolEvents: toolEvents,
      toolFailures: toolFailures,
      reasoning: reasoning,
      isError: isError,
      isPending: isPending,
    );
  }

  void _bumpMessages(String chatId) {
    _messageVersions[chatId] = (_messageVersions[chatId] ?? 0) + 1;
  }
}
