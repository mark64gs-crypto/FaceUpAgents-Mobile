import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/models.dart';
import '../state/app_state.dart';
import 'widgets/page_heading.dart';

class ChatsPage extends StatelessWidget {
  const ChatsPage({super.key, required this.state, required this.onOpenChat});

  final AppState state;
  final ValueChanged<ChatThread> onOpenChat;

  Future<void> _createChat(BuildContext context) async {
    final thread = await state.createChat();
    if (!context.mounted) return;
    onOpenChat(thread);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final insets = pageInsets(MediaQuery.sizeOf(context).width);
    return ListView(
      padding: insets.copyWith(top: 26, bottom: 118),
      children: [
        PageHeading(
          title: state.t('chatsTitle'),
          description: state.t('chatsDescription'),
        ),
        const SizedBox(height: 22),
        InkWell(
          onTap: () => _createChat(context),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    state.t('newChat'),
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                ),
                Icon(Icons.add_rounded, size: 24, color: palette.textPrimary),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (state.chats.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 40),
            child: Column(
              children: [
                Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 34,
                  color: palette.textSecondary.withValues(alpha: 0.6),
                ),
                const SizedBox(height: 12),
                Text(
                  state.t('chatsEmpty'),
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w300,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  state.t('chatsEmptyHint'),
                  style: TextStyle(
                    color: palette.textSecondary.withValues(alpha: 0.7),
                    fontSize: 12,
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ],
            ),
          )
        else
          for (final thread in state.chats) ...[
            _ChatCard(
              title: thread.title.trim().isEmpty
                  ? state.t('newChatTitle')
                  : thread.title,
              generating: state.isGenerating(thread.id),
              onOpen: () => onOpenChat(thread),
              onRename: () => _rename(context, thread),
              onDelete: () => _delete(context, thread),
              renameLabel: state.t('renameChat'),
              deleteLabel: state.t('deleteChat'),
            ),
            const SizedBox(height: 8),
          ],
      ],
    );
  }

  Future<void> _rename(BuildContext context, ChatThread thread) async {
    final controller = TextEditingController(
      text: thread.title.trim().isEmpty ? '' : thread.title,
    );
    final palette = AppPalette.of(context);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: palette.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          state.t('renameChat'),
          style: TextStyle(
            color: palette.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: palette.textPrimary),
          decoration: InputDecoration(
            hintText: state.t('chatName'),
            filled: true,
            fillColor: palette.settingsRow,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(state.t('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(state.t('save')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.trim().isEmpty) return;
    await state.renameChat(thread, result);
  }

  Future<void> _delete(BuildContext context, ChatThread thread) async {
    final palette = AppPalette.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: palette.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          state.t('deleteChatQuestion'),
          style: TextStyle(
            color: palette.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          state.t('deleteChatBody'),
          style: TextStyle(
            color: palette.textSecondary,
            fontSize: 14,
            fontWeight: FontWeight.w300,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(state.t('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: palette.danger),
            child: Text(state.t('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await state.deleteChat(thread);
  }
}

class _ChatCard extends StatelessWidget {
  const _ChatCard({
    required this.title,
    required this.generating,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
    required this.renameLabel,
    required this.deleteLabel,
  });

  final String title;
  final bool generating;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final String renameLabel;
  final String deleteLabel;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Material(
      color: palette.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: palette.textPrimary.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        onTap: onOpen,
        customBorder: const StadiumBorder(),
        child: SizedBox(
          height: 44,
          child: Row(
            children: [
              const SizedBox(width: 13),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ),
              if (generating)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: palette.textSecondary,
                    ),
                  ),
                ),
              IconButton(
                onPressed: onRename,
                visualDensity: VisualDensity.compact,
                iconSize: 19,
                tooltip: renameLabel,
                icon: Icon(Icons.edit_outlined, color: palette.textPrimary),
              ),
              IconButton(
                onPressed: onDelete,
                visualDensity: VisualDensity.compact,
                iconSize: 19,
                tooltip: deleteLabel,
                icon: Icon(Icons.delete_outline_rounded, color: palette.danger),
              ),
              const SizedBox(width: 3),
            ],
          ),
        ),
      ),
    );
  }
}
