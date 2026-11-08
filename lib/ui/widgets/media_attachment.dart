import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/app_strings.dart';
import '../../core/app_theme.dart';
import '../../core/models.dart';

Future<void> openImagePreview(BuildContext context, String path) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.88),
    builder: (context) => Dialog.fullscreen(
      backgroundColor: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 5,
                child: Center(child: Image.file(File(path))),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: IconButton.filledTonal(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

Future<void> openVideoPreview(BuildContext context, ChatAttachment attachment) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _VideoScreen(attachment: attachment),
    ),
  );
}

class MessageAttachmentView extends StatelessWidget {
  const MessageAttachmentView({
    super.key,
    required this.attachment,
    this.compact = false,
  });

  final ChatAttachment attachment;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return switch (attachment.kind) {
      AttachmentKind.image => GestureDetector(
        onTap: () => openImagePreview(context, attachment.path),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: compact ? 72 : 240,
              maxHeight: compact ? 72 : 280,
            ),
            child: Image.file(
              File(attachment.path),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _broken(palette),
            ),
          ),
        ),
      ),
      AttachmentKind.video => GestureDetector(
        onTap: () => openVideoPreview(context, attachment),
        child: Container(
          width: compact ? 72 : 240,
          height: compact ? 72 : 150,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(compact ? 10 : 12),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (!compact)
                Positioned(
                  left: 10,
                  bottom: 8,
                  right: 10,
                  child: Text(
                    attachment.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 10),
                  ),
                ),
              Container(
                width: compact ? 28 : 46,
                height: compact ? 28 : 46,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.play_arrow_rounded,
                  size: compact ? 20 : 30,
                  color: Colors.black,
                ),
              ),
            ],
          ),
        ),
      ),
      AttachmentKind.file => Container(
        width: compact ? 72 : 230,
        height: compact ? 72 : 50,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: palette.settingsRow,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: palette.cardBorder),
        ),
        child: Row(
          children: [
            Icon(
              Icons.description_outlined,
              size: compact ? 24 : 20,
              color: palette.textSecondary,
            ),
            if (!compact) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  attachment.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.textPrimary, fontSize: 12),
                ),
              ),
            ],
          ],
        ),
      ),
    };
  }

  Widget _broken(AppPalette palette) {
    return Container(
      width: 200,
      height: 120,
      color: palette.settingsRow,
      child: Icon(Icons.broken_image_outlined, color: palette.textSecondary),
    );
  }
}

class PendingAttachmentTile extends StatelessWidget {
  const PendingAttachmentTile({
    super.key,
    required this.attachment,
    required this.onRemove,
  });

  final ChatAttachment attachment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        MessageAttachmentView(attachment: attachment, compact: true),
        Positioned(
          top: -7,
          right: -7,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: palette.textPrimary,
                shape: BoxShape.circle,
                border: Border.all(color: palette.background, width: 1.5),
              ),
              child: Icon(
                Icons.close_rounded,
                size: 14,
                color: palette.background,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _VideoScreen extends StatefulWidget {
  const _VideoScreen({required this.attachment});

  final ChatAttachment attachment;

  @override
  State<_VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<_VideoScreen> {
  VideoPlayerController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    final controller = VideoPlayerController.file(File(widget.attachment.path));
    _controller = controller;
    controller
        .initialize()
        .then((_) {
          if (!mounted) return;
          controller.play();
          setState(() {});
        })
        .catchError((Object error) {
          if (!mounted) return;
          setState(() => _error = error.toString());
        });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final strings = AppStrings(
      AppLanguage.fromCode(Localizations.localeOf(context).languageCode),
    );
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        strings.t('videoError'),
                        style: const TextStyle(color: Colors.white70),
                      ),
                    )
                  : controller == null || !controller.value.isInitialized
                  ? const CircularProgressIndicator(color: Colors.white)
                  : AspectRatio(
                      aspectRatio: controller.value.aspectRatio,
                      child: VideoPlayer(controller),
                    ),
            ),
            if (controller != null && controller.value.isInitialized)
              Center(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      if (controller.value.isPlaying) {
                        controller.pause();
                      } else {
                        controller.play();
                      }
                    });
                  },
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: controller.value.isPlaying ? 0 : 1,
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 38,
                      ),
                    ),
                  ),
                ),
              ),
            Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: IconButton.filledTonal(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
              ),
            ),
            if (controller != null && controller.value.isInitialized)
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: VideoProgressIndicator(
                    controller,
                    allowScrubbing: true,
                    colors: const VideoProgressColors(
                      playedColor: Colors.white,
                      bufferedColor: Colors.white38,
                      backgroundColor: Colors.white12,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
