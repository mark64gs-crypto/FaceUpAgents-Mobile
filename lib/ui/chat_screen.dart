import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_theme.dart';
import '../core/models.dart';
import '../services/ai_provider.dart';
import '../state/app_state.dart';
import 'widgets/app_top_bar.dart';
import 'widgets/detail_disclosure.dart';
import 'widgets/media_attachment.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.state,
    required this.thread,
    required this.onOpenApi,
  });

  final AppState state;
  final ChatThread thread;
  final VoidCallback onOpenApi;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const _maxFileBytes = 20 * 1024 * 1024;

  final _composer = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  final _imagePicker = ImagePicker();
  final _messages = <ChatMessage>[];
  final _pending = <ChatAttachment>[];
  final _expandedReasoning = <String>{};
  final _expandedSources = <String>{};

  late ChatThread _thread;
  ToolSettings _tools = const ToolSettings();
  ToolActivity _activity = ToolActivity.thinking;
  bool _loadingMessages = true;
  bool _sending = false;
  bool _showTools = false;
  int _lastVersion = 0;

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    _thread = widget.thread;
    _lastVersion = state.messageVersion(_thread.id);
    state.addListener(_onStateChanged);
    _loadMessages();
  }

  @override
  void dispose() {
    state.removeListener(_onStateChanged);
    _composer.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    final requestedVersion = state.messageVersion(_thread.id);
    final loaded = await state.messagesFor(_thread);
    if (!mounted) return;
    if (requestedVersion != state.messageVersion(_thread.id)) {
      await _loadMessages();
      return;
    }
    final job = state.generationJobFor(_thread.id);
    setState(() {
      _messages
        ..clear()
        ..addAll(
          loaded.where(
            (message) => !message.isPending || message.attachments.isNotEmpty,
          ),
        );
      _loadingMessages = false;
      _sending = job != null;
      if (job != null) _activity = job.activity;
      _lastVersion = requestedVersion;
    });
    _scrollToBottom(immediate: true);
  }

  void _onStateChanged() {
    if (!mounted) return;
    final version = state.messageVersion(_thread.id);
    if (version != _lastVersion) {
      _lastVersion = version;
      _loadMessages();
      return;
    }
    final job = state.generationJobFor(_thread.id);
    final sending = job != null;
    final activity = job?.activity ?? _activity;
    if (sending != _sending || activity != _activity) {
      setState(() {
        _sending = sending;
        _activity = activity;
      });
    }
  }

  void _scrollToBottom({bool immediate = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent;
      if (immediate) {
        _scroll.jumpTo(target);
      } else {
        _scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _toggleTheme() {
    final dark = Theme.of(context).brightness == Brightness.dark;
    state.setTheme(dark ? AppThemeChoice.light : AppThemeChoice.dark);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _errorText(Object error) => state.errorText(error);

  Future<void> _sendMessage() async {
    if (_sending) return;
    final text = _composer.text.trim();
    if (text.isEmpty && _pending.isEmpty) return;
    final model = state.modelFor(ModelCategory.text);
    final apiKey = model == null ? null : state.keyFor(model.provider);
    if (model == null || apiKey == null) {
      _showMessage(state.t('configureTitle'));
      return;
    }

    final attachments = List<ChatAttachment>.from(_pending);
    final user = state.createMessage(
      chatId: _thread.id,
      role: ChatRole.user,
      text: text,
      attachments: attachments,
    );
    await state.insertMessage(user);
    if (!mounted) return;
    final titleSource = text.isNotEmpty
        ? text
        : attachments.isEmpty
        ? ''
        : attachments.first.name;
    setState(() {
      _messages.add(user);
      _pending.clear();
      _composer.clear();
      _showTools = false;
      _sending = true;
      _activity = ToolActivity.thinking;
    });
    _focus.unfocus();
    _scrollToBottom();
    if (_thread.title.trim().isEmpty && titleSource.isNotEmpty) {
      await state.renameChat(_thread, trimUserMessage(titleSource));
    }
    await _startGeneration();
  }

  Future<void> _startGeneration() async {
    try {
      await state.generateReply(
        thread: _thread,
        messages: _contextWindow(),
        settings: _tools,
      );
    } catch (error) {
      if (mounted) setState(() => _sending = false);
      _showMessage(_errorText(error));
    }
  }

  Future<void> _stopGeneration() async {
    await state.stopGeneration(_thread.id);
    if (!mounted) return;
    setState(() {
      _sending = false;
      _activity = ToolActivity.thinking;
    });
  }

  Future<void> _retry(ChatMessage message) async {
    if (_sending ||
        state.isGenerating(_thread.id) ||
        _messages.isEmpty ||
        _messages.last.id != message.id) {
      return;
    }
    await state.deleteMessage(message.id);
    if (!mounted) return;
    setState(() {
      _messages.removeLast();
      _sending = true;
      _activity = ToolActivity.thinking;
    });
    await _startGeneration();
  }

  List<ChatMessage> _contextWindow() {
    const maxMessages = 40;
    const attachmentWindow = 6;
    final start = math.max(0, _messages.length - maxMessages);
    final window = _messages.sublist(start);
    final cutoff = math.max(0, window.length - attachmentWindow);
    return [
      for (var index = 0; index < window.length; index++)
        if (index < cutoff && window[index].attachments.isNotEmpty)
          ChatMessage(
            id: window[index].id,
            chatId: window[index].chatId,
            role: window[index].role,
            text: window[index].text,
            createdAt: window[index].createdAt,
            citations: window[index].citations,
            toolEvents: window[index].toolEvents,
            toolFailures: window[index].toolFailures,
            reasoning: window[index].reasoning,
            isError: window[index].isError,
          )
        else
          window[index],
    ];
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    _showMessage(state.t('copied'));
  }

  Future<void> _openCitation(ChatCitation citation) async {
    final uri = Uri.tryParse(citation.url);
    if (uri == null) return;
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) _showMessage(state.t('networkError'));
  }

  Future<void> _pickImage() async {
    try {
      final file = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2400,
        imageQuality: 92,
      );
      if (file == null) return;
      await _addPicked(
        path: file.path,
        name: file.name,
        kind: AttachmentKind.image,
      );
    } catch (error) {
      _showMessage(state.t('pickFailed'));
    }
  }

  Future<void> _pickVideo() async {
    final model = state.modelFor(ModelCategory.text);
    if (model == null) {
      _showMessage(state.t('configureTitle'));
      return;
    }
    if (!state.providers.supportsLocalVideoInput(model.provider)) {
      _showMessage(state.t('videoAttachmentUnsupported'));
      return;
    }
    try {
      final file = await _imagePicker.pickVideo(source: ImageSource.gallery);
      if (file == null) return;
      await _addPicked(
        path: file.path,
        name: file.name,
        kind: AttachmentKind.video,
      );
    } catch (error) {
      _showMessage(state.t('pickFailed'));
    }
  }

  Future<void> _pickFile() async {
    final model = state.modelFor(ModelCategory.text);
    if (model == null) {
      _showMessage(state.t('configureTitle'));
      return;
    }
    try {
      final file = await FilePicker.pickFile();
      if (file == null) return;
      final path = file.path;
      if (path != null) {
        await _addPicked(
          path: path,
          name: file.name,
          kind: AttachmentKind.file,
        );
      } else {
        await _addPickedBytes(
          bytes: await file.readAsBytes(),
          name: file.name,
          kind: AttachmentKind.file,
        );
      }
    } catch (error) {
      _showMessage(state.t('pickFailed'));
    }
  }

  Future<void> _addPicked({
    required String path,
    required String name,
    required AttachmentKind kind,
  }) async {
    final file = File(path);
    if (!file.existsSync()) {
      _showMessage(state.t('pickFailed'));
      return;
    }
    await _addPickedBytes(
      bytes: null,
      sourcePath: path,
      length: await file.length(),
      name: name,
      kind: kind,
    );
  }

  Future<void> _addPickedBytes({
    required String name,
    required AttachmentKind kind,
    Uint8List? bytes,
    String? sourcePath,
    int? length,
  }) async {
    final model = state.modelFor(ModelCategory.text);
    if (model == null) {
      _showMessage(state.t('configureTitle'));
      return;
    }
    final size = length ?? bytes?.length ?? 0;
    if (size > _maxFileBytes) {
      _showMessage(state.t('fileTooLarge'));
      return;
    }
    final mime =
        lookupMimeType(name) ??
        (sourcePath == null ? null : lookupMimeType(sourcePath)) ??
        '';
    if (kind == AttachmentKind.video &&
        !state.providers.supportsLocalVideoInput(model.provider)) {
      _showMessage(state.t('videoAttachmentUnsupported'));
      return;
    }
    if (kind == AttachmentKind.image &&
        (!mime.startsWith('image/') || mime.contains('svg'))) {
      _showMessage(state.t('unsupportedFileType'));
      return;
    }
    if (kind == AttachmentKind.file &&
        !_supportsDocument(model.provider, mime, name)) {
      _showMessage(state.t('unsupportedFileType'));
      return;
    }
    try {
      final attachment = bytes != null
          ? await state.mediaStore.importBytes(
              bytes: bytes,
              name: name,
              kind: kind,
              mimeType: mime,
            )
          : await state.mediaStore.importFile(
              sourcePath: sourcePath!,
              name: name,
              kind: kind,
              mimeType: mime,
            );
      if (!mounted) return;
      setState(() {
        _pending.add(attachment);
        _showTools = false;
      });
    } catch (error) {
      _showMessage(state.t('pickFailed'));
    }
  }

  bool _supportsDocument(AiProviderType provider, String mime, String name) {
    final lowerName = name.toLowerCase();
    if (mime == 'application/pdf') return true;
    if (mime.startsWith('text/') ||
        mime == 'application/json' ||
        mime == 'application/xml' ||
        lowerName.endsWith('.md') ||
        lowerName.endsWith('.csv')) {
      return true;
    }
    if (mime.contains('wordprocessingml') || mime == 'application/msword') {
      return provider == AiProviderType.polza;
    }
    return false;
  }

  void _toggleImageTool() {
    if (!_tools.imageGeneration) {
      final model = state.modelFor(ModelCategory.image);
      if (model == null || state.keyFor(model.provider) == null) {
        _showMessage(state.t('imageToolNotConfigured'));
        return;
      }
    }
    setState(
      () => _tools = _tools.copyWith(imageGeneration: !_tools.imageGeneration),
    );
  }

  void _toggleVideoTool() {
    if (!_tools.videoGeneration) {
      final model = state.modelFor(ModelCategory.video);
      if (model == null || state.keyFor(model.provider) == null) {
        _showMessage(state.t('videoToolNotConfigured'));
        return;
      }
    }
    setState(
      () => _tools = _tools.copyWith(videoGeneration: !_tools.videoGeneration),
    );
  }

  void _cycleReasoning() {
    setState(() => _tools = _tools.copyWith(reasoning: _tools.reasoning.next));
  }

  void _toggleSearch(SearchMode mode) {
    if (state.modelFor(ModelCategory.text) == null) {
      _showMessage(state.t('configureTitle'));
      return;
    }
    setState(() {
      _tools = _tools.copyWith(
        search: _tools.search == mode ? SearchMode.off : mode,
      );
    });
  }

  void _toggleTools() {
    FocusScope.of(context).unfocus();
    setState(() => _showTools = !_showTools);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Column(
        children: [
          AppTopBar(
            onBack: () => Navigator.of(context).pop(),
            onToggleTheme: _toggleTheme,
          ),
          Expanded(child: _messageList(palette)),
          if (_showTools) _toolPanel(palette),
          if (_pending.isNotEmpty) _pendingStrip(palette),
          _composerBar(palette),
        ],
      ),
    );
  }

  Widget _messageList(AppPalette palette) {
    final insets = pageInsets(MediaQuery.sizeOf(context).width);
    if (_loadingMessages) {
      return const Center(child: CircularProgressIndicator());
    }
    final hasModel = state.modelFor(ModelCategory.text) != null;
    return ListView(
      controller: _scroll,
      padding: EdgeInsets.fromLTRB(insets.left, 20, insets.right, 18),
      children: [
        if (!hasModel) _configureCard(palette),
        for (var index = 0; index < _messages.length; index++)
          _messageView(
            palette,
            _messages[index],
            isLast: index == _messages.length - 1,
          ),
        if (_sending) _activityBubble(palette),
      ],
    );
  }

  Widget _configureCard(AppPalette palette) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.key_rounded, size: 20, color: palette.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  state.t('configureTitle'),
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            state.t('configureBody'),
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w300,
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: widget.onOpenApi,
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                color: palette.providerActive,
                borderRadius: BorderRadius.circular(19),
              ),
              alignment: Alignment.center,
              child: Text(
                state.t('openApi'),
                style: TextStyle(
                  color: palette.providerActiveForeground,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _messageView(
    AppPalette palette,
    ChatMessage message, {
    required bool isLast,
  }) {
    final user = message.role == ChatRole.user;
    final width = MediaQuery.sizeOf(context).width;
    final maxBubbleWidth = width * 0.78;
    final reasoningExpanded = _expandedReasoning.contains(message.id);
    final sourcesExpanded = _expandedSources.contains(message.id);
    final searchEvents = message.toolEvents
        .where(
          (event) =>
              event == ChatToolEvent.webSearch ||
              event == ChatToolEvent.deepSearch,
        )
        .toList();
    final otherEvents = message.toolEvents
        .where(
          (event) =>
              event != ChatToolEvent.webSearch &&
              event != ChatToolEvent.deepSearch,
        )
        .toList();
    final hasSources = searchEvents.isNotEmpty || message.citations.isNotEmpty;
    return Padding(
      padding: EdgeInsets.only(bottom: user ? 20 : 16),
      child: Column(
        crossAxisAlignment: user
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Container(
            constraints: BoxConstraints(maxWidth: maxBubbleWidth),
            padding: const EdgeInsets.fromLTRB(15, 12, 15, 10),
            decoration: BoxDecoration(
              color: message.isError
                  ? palette.danger.withValues(alpha: 0.08)
                  : user
                  ? palette.userBubble
                  : palette.assistantBubble,
              borderRadius: user
                  ? const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                      bottomLeft: Radius.circular(20),
                      bottomRight: Radius.circular(6),
                    )
                  : BorderRadius.circular(18),
              border: message.isError
                  ? Border.all(color: palette.danger.withValues(alpha: 0.35))
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message.attachments.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final attachment in message.attachments)
                          MessageAttachmentView(attachment: attachment),
                      ],
                    ),
                  ),
                if (message.text.trim().isNotEmpty)
                  user
                      ? SelectableText(
                          message.text,
                          style: TextStyle(
                            color: message.isError
                                ? palette.danger
                                : palette.textPrimary,
                            fontSize: 16,
                            height: 1.4,
                            fontWeight: FontWeight.w400,
                          ),
                        )
                      : message.isError
                      ? Text(
                          message.text,
                          style: TextStyle(
                            color: palette.danger,
                            fontSize: 14,
                            height: 1.4,
                          ),
                        )
                      : MarkdownBody(
                          data: message.text,
                          selectable: true,
                          styleSheet: _markdownStyle(palette),
                        ),
                if (!user && !message.isPending) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _messageAction(
                        palette,
                        icon: Icons.copy_rounded,
                        onTap: () => _copy(message.text),
                      ),
                      if (isLast && !_sending) ...[
                        const SizedBox(width: 5),
                        _messageAction(
                          palette,
                          icon: Icons.refresh_rounded,
                          onTap: () => _retry(message),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (!user && message.toolFailures.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _toolFailureCard(
                palette,
                message.toolFailures,
                maxBubbleWidth,
              ),
            ),
          if (!user &&
              (message.reasoning.trim().isNotEmpty ||
                  otherEvents.isNotEmpty ||
                  hasSources))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (otherEvents.isNotEmpty) ...[
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final event in otherEvents)
                          _toolChip(palette, event),
                      ],
                    ),
                    if (message.reasoning.trim().isNotEmpty || hasSources)
                      const SizedBox(height: 6),
                  ],
                  if (message.reasoning.trim().isNotEmpty)
                    DetailDisclosure(
                      icon: Icons.psychology_alt_outlined,
                      title: state.t('reasoningTitle'),
                      expanded: reasoningExpanded,
                      maxWidth: maxBubbleWidth,
                      onTap: () => setState(() {
                        if (reasoningExpanded) {
                          _expandedReasoning.remove(message.id);
                        } else {
                          _expandedReasoning.add(message.id);
                        }
                      }),
                      body: Text(
                        message.reasoning,
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 12.5,
                          height: 1.48,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                    ),
                  if (hasSources)
                    DetailDisclosure(
                      icon: searchEvents.contains(ChatToolEvent.deepSearch)
                          ? Icons.manage_search_rounded
                          : Icons.public_rounded,
                      title: searchEvents.contains(ChatToolEvent.deepSearch)
                          ? state.t('toolDeepSearch')
                          : searchEvents.isNotEmpty
                          ? state.t('toolWebSearch')
                          : state.t('sources'),
                      badge: message.citations.isEmpty
                          ? null
                          : '${message.citations.length}',
                      expanded: sourcesExpanded,
                      maxWidth: maxBubbleWidth,
                      onTap: () => setState(() {
                        if (sourcesExpanded) {
                          _expandedSources.remove(message.id);
                        } else {
                          _expandedSources.add(message.id);
                        }
                      }),
                      body: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (searchEvents.isNotEmpty) ...[
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final event in searchEvents)
                                  _toolChip(palette, event),
                              ],
                            ),
                            const SizedBox(height: 8),
                          ],
                          _citationList(palette, message.citations),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _toolFailureCard(
    AppPalette palette,
    List<ChatToolFailure> failures,
    double maxWidth,
  ) {
    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
      decoration: BoxDecoration(
        color: palette.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.danger.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 16,
                color: palette.danger,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  state.t('generationFailedDetails'),
                  style: TextStyle(
                    color: palette.danger,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          for (final failure in failures)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${state.t(failure.kind == AttachmentKind.video ? 'videoGenerationFailed' : 'imageGenerationFailed')}: ${failure.message}',
                style: TextStyle(
                  color: palette.danger,
                  fontSize: 12,
                  height: 1.4,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          const SizedBox(height: 6),
          Text(
            state.t('toolFailureHint'),
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 11,
              height: 1.4,
              fontWeight: FontWeight.w300,
            ),
          ),
        ],
      ),
    );
  }

  Widget _citationList(AppPalette palette, List<ChatCitation> citations) {
    if (citations.isEmpty) {
      return Text(
        state.t('sourcesMissing'),
        style: TextStyle(
          color: palette.textTertiary,
          fontSize: 11.5,
          height: 1.4,
          fontWeight: FontWeight.w300,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final citation in citations) _citationTile(palette, citation),
      ],
    );
  }

  Widget _citationTile(AppPalette palette, ChatCitation citation) {
    final title = citation.title.trim().isEmpty
        ? citation.url
        : citation.title.trim();
    final host = Uri.tryParse(citation.url)?.host ?? '';
    return GestureDetector(
      onTap: () => _openCitation(citation),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                Icons.link_rounded,
                size: 14,
                color: palette.textTertiary,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 12,
                      height: 1.35,
                      fontWeight: FontWeight.w400,
                      decoration: TextDecoration.underline,
                      decorationColor: palette.textTertiary,
                    ),
                  ),
                  if (host.isNotEmpty)
                    Text(
                      host,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textTertiary,
                        fontSize: 10.5,
                        height: 1.3,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.open_in_new_rounded,
              size: 12,
              color: palette.textTertiary,
            ),
          ],
        ),
      ),
    );
  }

  MarkdownStyleSheet _markdownStyle(AppPalette palette) {
    final base = TextStyle(
      color: palette.textPrimary,
      fontSize: 15.5,
      height: 1.42,
      fontWeight: FontWeight.w400,
    );
    return MarkdownStyleSheet(
      p: base,
      pPadding: EdgeInsets.zero,
      h1: base.copyWith(fontSize: 21, fontWeight: FontWeight.w700),
      h1Padding: const EdgeInsets.only(top: 10, bottom: 4),
      h2: base.copyWith(fontSize: 18.5, fontWeight: FontWeight.w700),
      h2Padding: const EdgeInsets.only(top: 8, bottom: 3),
      h3: base.copyWith(fontSize: 16.5, fontWeight: FontWeight.w600),
      h3Padding: const EdgeInsets.only(top: 6, bottom: 2),
      strong: base.copyWith(fontWeight: FontWeight.w600),
      em: base.copyWith(fontStyle: FontStyle.italic),
      blockSpacing: 8,
      listIndent: 20,
      listBullet: base,
      code: TextStyle(
        color: palette.textPrimary,
        fontSize: 13,
        fontFamily: 'monospace',
        backgroundColor: palette.settingsRow,
      ),
      codeblockDecoration: BoxDecoration(
        color: palette.settingsRow,
        borderRadius: BorderRadius.circular(8),
      ),
      codeblockPadding: const EdgeInsets.all(10),
      blockquote: TextStyle(
        color: palette.textSecondary,
        fontSize: 14.5,
        height: 1.4,
      ),
      blockquoteDecoration: BoxDecoration(
        color: palette.settingsRow,
        border: Border(
          left: BorderSide(color: palette.textSecondary, width: 3),
        ),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      a: TextStyle(
        color: palette.textPrimary,
        fontSize: 15.5,
        decoration: TextDecoration.underline,
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: palette.divider)),
      ),
    );
  }

  Widget _messageAction(
    AppPalette palette, {
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: palette.settingsRow,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Icon(icon, size: 15, color: palette.textPrimary),
      ),
    );
  }

  Widget _toolChip(AppPalette palette, ChatToolEvent event) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: palette.settingsRow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.cardBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(event.icon, size: 13, color: palette.textSecondary),
          const SizedBox(width: 5),
          Text(
            state.t(event.localizationKey),
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 10.5,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _activityBubble(AppPalette palette) {
    final label = switch (_activity) {
      ToolActivity.thinking => state.t('thinking'),
      ToolActivity.searching => state.t('searchingWeb'),
      ToolActivity.reading => state.t('readingSources'),
      ToolActivity.generatingImage => state.t('generatingImage'),
      ToolActivity.generatingVideo => state.t('generatingVideo'),
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        decoration: BoxDecoration(
          color: palette.assistantBubble,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                color: palette.textSecondary,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w300,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pendingStrip(AppPalette palette) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
      child: SizedBox(
        height: 82,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _pending.length,
          separatorBuilder: (_, _) => const SizedBox(width: 14),
          itemBuilder: (context, index) {
            final attachment = _pending[index];
            return PendingAttachmentTile(
              attachment: attachment,
              onRemove: () => setState(() => _pending.removeAt(index)),
            );
          },
        ),
      ),
    );
  }

  Widget _composerBar(AppPalette palette) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Container(
          height: 72,
          decoration: BoxDecoration(
            color: palette.background,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: palette.composerBorder, width: 0.8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              _roundComposerButton(
                palette,
                icon: _showTools
                    ? Icons.close_rounded
                    : Icons.attach_file_rounded,
                onTap: _toggleTools,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: _composer,
                  focusNode: _focus,
                  maxLines: 4,
                  minLines: 1,
                  textCapitalization: TextCapitalization.sentences,
                  onTap: () {
                    if (_showTools) setState(() => _showTools = false);
                  },
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w300,
                  ),
                  decoration: InputDecoration(
                    hintText: state.t('composerHint'),
                    hintStyle: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 16,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _composer,
                builder: (context, value, _) {
                  final enabled =
                      value.text.trim().isNotEmpty || _pending.isNotEmpty;
                  final sending = _sending;
                  return _roundComposerButton(
                    palette,
                    icon: sending ? Icons.stop_rounded : null,
                    tooltip: sending
                        ? state.t('stopGeneration')
                        : state.t('send'),
                    opacity: sending || enabled ? 1 : 0.45,
                    onTap: sending
                        ? _stopGeneration
                        : enabled
                        ? _sendMessage
                        : null,
                    child: const Icon(Icons.arrow_upward_rounded, size: 24),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roundComposerButton(
    AppPalette palette, {
    IconData? icon,
    Widget? child,
    VoidCallback? onTap,
    bool busy = false,
    double opacity = 1,
    String? tooltip,
  }) {
    final button = GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: palette.inputFill,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: busy
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: palette.textPrimary,
                  ),
                )
              : icon != null
              ? Icon(icon, size: 24, color: palette.textPrimary)
              : IconTheme(
                  data: IconThemeData(color: palette.textPrimary),
                  child: child ?? const SizedBox.shrink(),
                ),
        ),
      ),
    );
    if (tooltip == null) return Opacity(opacity: opacity, child: button);
    return Opacity(
      opacity: opacity,
      child: Tooltip(message: tooltip, child: button),
    );
  }

  Widget _toolPanel(AppPalette palette) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: palette.background,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: palette.composerBorder.withValues(alpha: 0.8),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: _attachmentChoice(
                    palette,
                    icon: Icons.photo_library_outlined,
                    label: state.t('image'),
                    onTap: _pickImage,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _attachmentChoice(
                    palette,
                    icon: Icons.videocam_outlined,
                    label: state.t('video'),
                    onTap: _pickVideo,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _attachmentChoice(
                    palette,
                    icon: Icons.description_outlined,
                    label: state.t('file'),
                    onTap: _pickFile,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _toolRow(
              palette,
              icon: Icons.psychology_outlined,
              label: state.t('reasoningMode'),
              trailing: state.t(_tools.reasoning.localizationKey),
              selected: _tools.reasoning != ReasoningLevel.off,
              onTap: _cycleReasoning,
            ),
            _toolRow(
              palette,
              icon: Icons.image_outlined,
              label: state.t('generateImage'),
              selected: _tools.imageGeneration,
              onTap: _toggleImageTool,
            ),
            _toolRow(
              palette,
              icon: Icons.videocam_outlined,
              label: state.t('generateVideo'),
              selected: _tools.videoGeneration,
              onTap: _toggleVideoTool,
            ),
            _toolRow(
              palette,
              icon: Icons.public_rounded,
              label: state.t('webSearch'),
              selected: _tools.search == SearchMode.web,
              onTap: () => _toggleSearch(SearchMode.web),
            ),
            _toolRow(
              palette,
              icon: Icons.manage_search_rounded,
              label: state.t('deepSearch'),
              selected: _tools.search == SearchMode.deep,
              onTap: () => _toggleSearch(SearchMode.deep),
              last: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _attachmentChoice(
    AppPalette palette, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 88,
        decoration: BoxDecoration(
          color: palette.toolCard,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: palette.textPrimary),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolRow(
    AppPalette palette, {
    required IconData icon,
    required String label,
    String? trailing,
    bool selected = false,
    required VoidCallback onTap,
    bool last = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(19),
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: palette.toolCard,
            borderRadius: BorderRadius.circular(19),
            border: selected
                ? Border.all(color: palette.textPrimary.withValues(alpha: 0.45))
                : null,
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: palette.textPrimary),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
              if (trailing != null)
                Text(
                  trailing,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w300,
                  ),
                )
              else if (selected)
                Icon(
                  Icons.check_circle_rounded,
                  size: 17,
                  color: palette.textPrimary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
