import '../core/models.dart';
import 'ai_provider.dart';
import 'http_utils.dart';
import 'media_store.dart';
import 'provider_registry.dart';

class ChatService {
  ChatService({ProviderRegistry? registry, MediaStore? mediaStore})
    : registry = registry ?? ProviderRegistry(),
      mediaStore = mediaStore ?? MediaStore();

  final ProviderRegistry registry;
  final MediaStore mediaStore;

  Future<ChatCompletion> complete({
    required List<ChatMessage> messages,
    required ModelOption textModel,
    required String apiKey,
    required ToolSettings settings,
    required void Function(ToolActivity activity) onActivity,
    Future<void> Function(ChatAttachment attachment)? onAttachment,
    ModelOption? imageModel,
    String? imageApiKey,
    ModelOption? videoModel,
    String? videoApiKey,
    ImageResolution imageResolution = ImageResolution.oneK,
    CancellationToken? cancellation,
  }) async {
    final attachments = <ChatAttachment>[];
    final toolEvents = <ChatToolEvent>[];
    final toolFailures = <ChatToolFailure>[];
    final provider = registry.forType(textModel.provider);

    ChatToolFailure? failureFor(AttachmentKind kind) {
      for (final failure in toolFailures) {
        if (failure.kind == kind) return failure;
      }
      return null;
    }

    Future<void> runTool(
      AttachmentKind kind,
      Future<void> Function() action,
    ) async {
      cancellation?.throwIfCancelled();
      final previous = failureFor(kind);
      if (previous != null) {
        // Do not bill another provider request when the same media model has
        // already rejected this turn. The model still receives a clear error.
        throw ApiException(previous.message);
      }
      try {
        await action();
      } on CancellationException {
        rethrow;
      } catch (error) {
        final message = error is ApiException
            ? error.message
            : error.toString();
        toolFailures.add(ChatToolFailure(kind: kind, message: message));
        rethrow;
      } finally {
        onActivity(ToolActivity.thinking);
      }
    }

    final runtime = ChatToolRuntime(
      reasoning: settings.reasoning,
      search: settings.search,
      onActivity: onActivity,
      generateImage: imageModel == null || (imageApiKey ?? '').isEmpty
          ? null
          : (prompt, aspectRatio) async {
              late ChatAttachment saved;
              await runTool(AttachmentKind.image, () async {
                onActivity(ToolActivity.generatingImage);
                final generated = await registry
                    .forType(imageModel.provider)
                    .generateImage(
                      apiKey: imageApiKey!,
                      model: imageModel.id,
                      prompt: prompt,
                      aspectRatio: aspectRatio,
                      resolution: imageResolution,
                      cancellation: cancellation,
                    );
                saved = await mediaStore.saveGenerated(
                  generated,
                  AttachmentKind.image,
                );
                attachments.add(saved);
                toolEvents.add(ChatToolEvent.imageGenerated);
                await onAttachment?.call(saved);
              });
              return 'Image generated successfully and shown to the user as ${saved.name}.';
            },
      generateVideo: videoModel == null || (videoApiKey ?? '').isEmpty
          ? null
          : (prompt, aspectRatio, seconds) async {
              late ChatAttachment saved;
              await runTool(AttachmentKind.video, () async {
                onActivity(ToolActivity.generatingVideo);
                final generated = await registry
                    .forType(videoModel.provider)
                    .generateVideo(
                      apiKey: videoApiKey!,
                      model: videoModel.id,
                      prompt: prompt,
                      aspectRatio: aspectRatio,
                      seconds: seconds,
                      cancellation: cancellation,
                    );
                saved = await mediaStore.saveGenerated(
                  generated,
                  AttachmentKind.video,
                );
                attachments.add(saved);
                toolEvents.add(ChatToolEvent.videoGenerated);
                await onAttachment?.call(saved);
              });
              return 'Video generated successfully and shown to the user as ${saved.name}.';
            },
    );

    ProviderChatResult result;
    try {
      result = await provider.chat(
        apiKey: apiKey,
        model: textModel.id,
        messages: messages,
        runtime: runtime,
        cancellation: cancellation,
      );
    } on CancellationException {
      rethrow;
    } catch (error) {
      // Some models stop with an "empty response" after a tool call even
      // though the media was already generated and saved. Never throw that
      // result away: return the attachments and any tool failure instead.
      if (attachments.isEmpty && toolFailures.isEmpty) rethrow;
      return ChatCompletion(
        text: '',
        attachments: List.unmodifiable(attachments),
        toolEvents: List.unmodifiable(toolEvents),
        toolFailures: List.unmodifiable(toolFailures),
      );
    }

    if (result.usedWebSearch) {
      toolEvents.insert(
        0,
        settings.search == SearchMode.deep
            ? ChatToolEvent.deepSearch
            : ChatToolEvent.webSearch,
      );
    }

    return ChatCompletion(
      text: result.text,
      reasoning: result.reasoning,
      citations: result.citations,
      attachments: List.unmodifiable(attachments),
      toolEvents: List.unmodifiable(toolEvents),
      toolFailures: List.unmodifiable(toolFailures),
    );
  }
}
