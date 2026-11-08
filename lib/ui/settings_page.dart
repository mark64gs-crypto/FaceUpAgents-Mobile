import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_theme.dart';
import '../core/models.dart';
import '../state/app_state.dart';
import 'widgets/page_heading.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.state});

  final AppState state;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _version = '0.0.1 beta';

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _version = info.version.isEmpty ? '0.0.1 beta' : '${info.version} beta';
      });
    } on Exception {
      // Keep the bundled default when the platform channel is unavailable.
    }
  }

  Future<void> _openDeveloper() async {
    final uri = Uri.parse('https://github.com/mark64gs-crypto');
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) _showLinkError();
    } catch (_) {
      _showLinkError();
    }
  }

  void _showLinkError() {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(state.t('linkOpenFailed'))));
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final insets = pageInsets(MediaQuery.sizeOf(context).width);
    return ListView(
      padding: insets.copyWith(top: 26, bottom: 118),
      children: [
        PageHeading(
          title: state.t('settingsTitle'),
          description: state.t('settingsDescription'),
        ),
        const SizedBox(height: 22),
        _themePanel(palette),
        const SizedBox(height: 12),
        _fieldPanel(
          palette,
          label: state.t('fontTitle'),
          child: _dropdown<AppFontChoice>(
            palette: palette,
            value: state.font,
            items: AppFontChoice.values,
            label: (value) => value == AppFontChoice.inter
                ? state.t('fontInter')
                : state.t('fontSystem'),
            onChanged: (value) {
              if (value != null) state.setFont(value);
            },
          ),
        ),
        const SizedBox(height: 12),
        _fieldPanel(
          palette,
          label: state.t('languageTitle'),
          child: _dropdown<AppLanguage>(
            palette: palette,
            value: state.language,
            items: AppLanguage.values,
            label: (value) => switch (value) {
              AppLanguage.english => state.t('languageEnglish'),
              AppLanguage.russian => state.t('languageRussian'),
              AppLanguage.spanish => state.t('languageSpanish'),
            },
            onChanged: (value) {
              if (value != null) state.setLanguage(value);
            },
          ),
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 8),
          child: Text(
            state.t('aboutTitle'),
            style: AppTypography.settingsLabel.copyWith(
              color: palette.textPrimary,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: palette.settingsPanel,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: palette.cardBorder),
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              _infoRow(
                palette,
                label: state.t('developer'),
                value: 'SatiRa',
                onTap: _openDeveloper,
              ),
              const SizedBox(height: 8),
              _infoRow(palette, label: state.t('version'), value: _version),
            ],
          ),
        ),
      ],
    );
  }

  Widget _themePanel(AppPalette palette) {
    return Container(
      decoration: BoxDecoration(
        color: palette.settingsPanel,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: palette.cardBorder),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            state.t('themeTitle'),
            style: AppTypography.settingsLabel.copyWith(
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final choice in AppThemeChoice.values) ...[
                Expanded(
                  child: _themeChoice(
                    palette,
                    choice: choice,
                    label: switch (choice) {
                      AppThemeChoice.light => state.t('themeLight'),
                      AppThemeChoice.dark => state.t('themeDark'),
                      AppThemeChoice.system => state.t('themeSystem'),
                    },
                  ),
                ),
                if (choice != AppThemeChoice.values.last)
                  const SizedBox(width: 8),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _themeChoice(
    AppPalette palette, {
    required AppThemeChoice choice,
    required String label,
  }) {
    final selected = state.theme == choice;
    return GestureDetector(
      onTap: () => state.setTheme(choice),
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w200,
            ),
          ),
          const SizedBox(height: 6),
          AspectRatio(
            aspectRatio: 1.05,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                border: Border.all(
                  color: selected ? palette.textPrimary : palette.cardBorder,
                  width: selected ? 1.4 : 0.8,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(1),
                child: _ThemePreview(choice: choice),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 15,
              height: 15,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? palette.textPrimary : palette.textSecondary,
                  width: 1,
                ),
                color: selected ? palette.textPrimary : Colors.transparent,
              ),
              child: selected
                  ? Icon(Icons.circle, size: 7, color: palette.background)
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _fieldPanel(
    AppPalette palette, {
    required String label,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: palette.settingsPanel,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: palette.cardBorder),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Text(
            label,
            style: AppTypography.settingsLabel.copyWith(
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _dropdown<T>({
    required AppPalette palette,
    required T value,
    required List<T> items,
    required String Function(T) label,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: palette.cardBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          isDense: true,
          icon: Icon(
            Icons.expand_more_rounded,
            size: 20,
            color: palette.textPrimary,
          ),
          style: TextStyle(
            color: palette.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w300,
          ),
          dropdownColor: palette.background,
          borderRadius: BorderRadius.circular(10),
          items: [
            for (final item in items)
              DropdownMenuItem<T>(
                value: item,
                child: Text(label(item), overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _infoRow(
    AppPalette palette, {
    required String label,
    required String value,
    VoidCallback? onTap,
  }) {
    final row = Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: palette.settingsRow,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: palette.cardBorder),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w300,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w300,
              decoration: onTap == null ? null : TextDecoration.underline,
              decorationColor: palette.textSecondary,
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 5),
            Icon(
              Icons.open_in_new_rounded,
              size: 13,
              color: palette.textSecondary,
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return row;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: row,
    );
  }
}

class _ThemePreview extends StatelessWidget {
  const _ThemePreview({required this.choice});

  final AppThemeChoice choice;

  @override
  Widget build(BuildContext context) {
    final dark = switch (choice) {
      AppThemeChoice.light => false,
      AppThemeChoice.dark => true,
      AppThemeChoice.system => true,
    };
    final background = dark ? const Color(0xFF333333) : const Color(0xFFECEBEB);
    final line = dark ? const Color(0xFF545454) : const Color(0xFFFFFFFF);
    final muted = dark ? const Color(0xFF7E7E7E) : const Color(0xFF9F9F9F);
    return Container(
      color: background,
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (choice == AppThemeChoice.system)
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _miniPage(const Color(0xFFECEBEB))),
                  Expanded(child: _miniPage(const Color(0xFF333333))),
                ],
              ),
            )
          else
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 7,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: line,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Container(
                    height: 7,
                    width: 40,
                    decoration: BoxDecoration(
                      color: muted,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Container(
                        width: 16,
                        height: 6,
                        decoration: BoxDecoration(
                          color: line,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        width: 10,
                        height: 6,
                        decoration: BoxDecoration(
                          color: muted,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _miniPage(Color color) {
    return Container(
      color: color,
      padding: const EdgeInsets.all(5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 4, color: const Color(0xFFBFBFBF)),
          const SizedBox(height: 3),
          Container(height: 4, width: 16, color: const Color(0xFF8F8F8F)),
        ],
      ),
    );
  }
}
