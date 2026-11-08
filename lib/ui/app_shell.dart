import 'package:flutter/material.dart';

import '../core/models.dart';
import '../state/app_state.dart';
import 'api_page.dart';
import 'chat_screen.dart';
import 'chats_page.dart';
import 'settings_page.dart';
import 'widgets/app_top_bar.dart';
import 'widgets/floating_nav.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.state});

  final AppState state;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  AppState get state => widget.state;

  void _selectPage(int index) {
    if (_index == index) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _index = index);
  }

  void _toggleTheme() {
    final dark = Theme.of(context).brightness == Brightness.dark;
    state.setTheme(dark ? AppThemeChoice.light : AppThemeChoice.dark);
  }

  Future<void> _openChat(ChatThread thread) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(
          state: state,
          thread: thread,
          onOpenApi: () {
            Navigator.of(context).pop();
            _selectPage(0);
          },
        ),
      ),
    );
    if (mounted) await state.refreshChats();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              AppTopBar(onToggleTheme: _toggleTheme),
              Expanded(
                child: IndexedStack(
                  index: _index,
                  children: [
                    ApiPage(state: state),
                    ChatsPage(state: state, onOpenChat: _openChat),
                    SettingsPage(state: state),
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.only(bottom: 22),
              child: Center(
                child: FloatingNav(
                  index: _index,
                  onSelect: _selectPage,
                  labels: [
                    state.t('navApi'),
                    state.t('navChats'),
                    state.t('navSettings'),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
