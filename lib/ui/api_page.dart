import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/models.dart';
import '../services/http_utils.dart';
import '../state/app_state.dart';
import 'widgets/model_picker.dart';
import 'widgets/page_heading.dart';

class ApiPage extends StatefulWidget {
  const ApiPage({super.key, required this.state});

  final AppState state;

  @override
  State<ApiPage> createState() => _ApiPageState();
}

class _ApiPageState extends State<ApiPage> {
  final Map<ModelCategory, AiProviderType> _drafts = {};
  final Map<ModelCategory, TextEditingController> _keys = {};
  final Map<ModelCategory, bool> _obscure = {};
  final Map<ModelCategory, bool> _busy = {};
  final Map<ModelCategory, bool> _editingKey = {};
  final Map<ModelCategory, List<ModelOption>> _catalogs = {};
  bool _refreshing = false;

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    for (final category in ModelCategory.values) {
      final active = state.modelFor(category);
      final initial =
          active != null && state.providers.supports(active.provider, category)
          ? active.provider
          : AiProviderType.openai;
      _drafts[category] = initial;
      _keys[category] = TextEditingController(
        text: state.keyFor(initial) ?? '',
      );
      _obscure[category] = true;
      _busy[category] = false;
      _editingKey[category] = false;
    }
  }

  @override
  void dispose() {
    for (final controller in _keys.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _selectProvider(ModelCategory category, AiProviderType provider) {
    if (_drafts[category] == provider) return;
    setState(() {
      _drafts[category] = provider;
      _keys[category]!.text = state.keyFor(provider) ?? '';
      _obscure[category] = true;
      _editingKey[category] = false;
      _catalogs.remove(category);
    });
  }

  /// One-tap refresh: re-fetches the model catalog for every connected
  /// category using the stored keys, without re-entering anything.
  Future<void> _refreshAll() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    final result = await state.refreshApi(providers: _drafts);
    if (!mounted) return;
    setState(() {
      _refreshing = false;
      _catalogs.addAll(result.catalogs);
    });
    if (!result.hasAnything) {
      _showMessage(state.t('apiRefreshNothing'));
    } else if (result.failures.isEmpty) {
      _showMessage(
        state.strings.t(
          'apiRefreshed',
          args: {'count': '${result.catalogs.length}'},
        ),
      );
    } else {
      _showMessage(
        state.strings.t(
          'apiRefreshPartial',
          args: {
            'count': '${result.catalogs.length}',
            'details': result.failures.join('; '),
          },
        ),
      );
    }
  }

  Widget _refreshButton(AppPalette palette) {
    return Tooltip(
      message: state.t('refreshApi'),
      child: InkWell(
        onTap: _refreshing ? null : _refreshAll,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: palette.inputFill.withValues(alpha: 0.73),
            shape: BoxShape.circle,
            border: Border.all(
              color: palette.inputBorder.withValues(alpha: 0.28),
            ),
          ),
          child: Center(
            child: _refreshing
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      color: palette.textSecondary,
                    ),
                  )
                : Icon(
                    Icons.refresh_rounded,
                    size: 24,
                    color: palette.textPrimary,
                  ),
          ),
        ),
      ),
    );
  }

  Future<void> _deleteKey(ModelCategory category) async {
    final provider = _drafts[category]!;
    final palette = AppPalette.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: palette.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          state.t('deleteKeyQuestion'),
          style: TextStyle(
            color: palette.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          state.strings.t('deleteKeyBody', args: {'provider': provider.label}),
          style: TextStyle(
            color: palette.textSecondary,
            fontSize: 14,
            fontWeight: FontWeight.w300,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(state.t('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: palette.danger),
            child: Text(state.t('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await state.clearProviderKey(provider);
    } catch (_) {
      if (mounted) _showMessage(state.t('unknownError'));
      return;
    }
    if (!mounted) return;
    setState(() {
      for (final item in ModelCategory.values) {
        if (_drafts[item] == provider) {
          _keys[item]!.clear();
          _editingKey[item] = false;
          _obscure[item] = true;
          _catalogs.remove(item);
        }
      }
    });
    _showMessage(state.t('keyDeleted'));
  }

  Future<void> _connect(ModelCategory category) async {
    final provider = _drafts[category]!;
    if (!state.providers.supports(provider, category)) return;
    setState(() => _busy[category] = true);
    try {
      final result = await state.connectProvider(
        provider: provider,
        category: category,
        apiKey: _keys[category]!.text,
      );
      if (!mounted) return;
      setState(() {
        _busy[category] = false;
        _editingKey[category] = false;
        _catalogs[category] = result.models;
      });
      await _chooseFrom(context, result);
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy[category] = false);
      final message = error is ApiException && error.isAuthorizationError
          ? state.t('keyInvalid')
          : error is ApiException
          ? error.message
          : error.toString();
      _showMessage(message);
    }
  }

  Future<void> _openModels(ModelCategory category) async {
    final provider = _drafts[category]!;
    final apiKey = state.keyFor(provider);
    if (apiKey == null || apiKey.isEmpty) {
      setState(() => _editingKey[category] = true);
      return;
    }
    final cached = _catalogs[category];
    if (cached != null && cached.isNotEmpty) {
      await _chooseFrom(
        context,
        ConnectResult(
          provider: provider,
          category: category,
          models: cached,
          supported: true,
        ),
      );
      return;
    }
    setState(() => _busy[category] = true);
    try {
      final models = await state.providers
          .forType(provider)
          .listModels(apiKey: apiKey, category: category);
      if (!mounted) return;
      setState(() {
        _busy[category] = false;
        _catalogs[category] = models;
      });
      if (models.isEmpty) {
        _showMessage(state.t('noModels'));
        return;
      }
      await _chooseFrom(
        context,
        ConnectResult(
          provider: provider,
          category: category,
          models: models,
          supported: true,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy[category] = false);
      _showMessage(error is ApiException ? error.message : error.toString());
    }
  }

  Future<void> _chooseFrom(BuildContext context, ConnectResult result) async {
    final selected = await showModelPicker(
      context,
      strings: state.strings,
      result: result,
      current: state.modelFor(result.category),
    );
    if (selected != null) {
      await state.selectModel(selected);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final insets = pageInsets(MediaQuery.sizeOf(context).width);
    return ListView(
      padding: insets.copyWith(top: 26, bottom: 118),
      children: [
        PageHeading(
          title: state.t('apiTitle'),
          description: state.t('apiDescription'),
          trailing: _refreshButton(palette),
        ),
        const SizedBox(height: 22),
        for (final category in ModelCategory.values) ...[
          _buildCard(category, palette),
          if (category != ModelCategory.video) const SizedBox(height: 22),
        ],
      ],
    );
  }

  Widget _buildCard(ModelCategory category, AppPalette palette) {
    final provider = _drafts[category]!;
    final active = state.modelFor(category);
    final supported = state.providers.supports(provider, category);
    final hasKey = state.hasKey(provider);
    final busy = _busy[category] ?? false;
    final editingKey = _editingKey[category] ?? false;
    final showModelRow = supported && hasKey && !editingKey;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? palette.cardBorder.withValues(alpha: 0.55)
              : palette.cardBorder,
        ),
        boxShadow: [
          BoxShadow(
            color: palette.shadow.withValues(alpha: isDark ? 0.18 : 0.10),
            blurRadius: 36,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: palette.inputFill.withValues(alpha: 0.73),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: palette.inputBorder.withValues(alpha: 0.28),
                  ),
                ),
                child: Icon(
                  category.icon,
                  size: 23,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.t(category.localizationKey),
                      style: AppTypography.cardTitle.copyWith(
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      state.t(category.subtitleKey),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.cardSubtitle.copyWith(
                        color: palette.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                height: 20,
                padding: const EdgeInsets.symmetric(horizontal: 7),
                decoration: BoxDecoration(
                  color: palette.chip,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: hasKey
                            ? palette.textPrimary
                            : palette.textPrimary.withValues(alpha: 0.28),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      provider.label,
                      style: AppTypography.chip.copyWith(
                        color: palette.chipForeground,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final option in AiProviderType.values) ...[
                Expanded(child: _providerChip(category, option, palette)),
                if (option != AiProviderType.values.last)
                  const SizedBox(width: 6),
              ],
            ],
          ),
          const SizedBox(height: 10),
          if (!supported)
            _unsupportedRow(palette)
          else if (showModelRow) ...[
            _modelRow(category, palette, active, busy, hasKey),
            if (category == ModelCategory.image) ...[
              const SizedBox(height: 10),
              _resolutionRow(palette),
            ],
          ] else
            _keyRow(category, palette, busy, hasKey),
        ],
      ),
    );
  }

  Widget _providerChip(
    ModelCategory category,
    AiProviderType provider,
    AppPalette palette,
  ) {
    final active = _drafts[category] == provider;
    return GestureDetector(
      onTap: () => _selectProvider(category, provider),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? palette.providerActive : palette.providerInactive,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: active
                ? palette.providerActive
                : palette.providerInactiveBorder,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: palette.shadow.withValues(alpha: 0.25),
                    blurRadius: 4,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active
                        ? palette.providerActiveForeground
                        : palette.providerInactiveForeground,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  provider.label,
                  style: AppTypography.chip.copyWith(
                    color: active
                        ? palette.providerActiveForeground
                        : palette.providerInactiveForeground,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _unsupportedRow(AppPalette palette) {
    return Container(
      height: 38,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: palette.inputFill.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.centerLeft,
      child: Text(
        state.t('providerCategoryUnsupported'),
        style: AppTypography.cardSubtitle.copyWith(
          color: palette.textSecondary,
        ),
      ),
    );
  }

  Widget _resolutionRow(AppPalette palette) {
    final selected = state.imageResolution;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.photo_size_select_large_rounded,
              size: 16,
              color: palette.textSecondary,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                state.t('imageResolution'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            for (final resolution in ImageResolution.values) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => state.setImageResolution(resolution),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: 26,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected == resolution
                        ? palette.providerActive
                        : palette.chip,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: selected == resolution
                          ? palette.providerActive
                          : palette.providerInactiveBorder,
                    ),
                  ),
                  child: Text(
                    state.t(resolution.localizationKey),
                    style: TextStyle(
                      color: selected == resolution
                          ? palette.providerActiveForeground
                          : palette.chipForeground,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text(
          state.t('imageResolutionHint'),
          style: TextStyle(
            color: palette.textTertiary,
            fontSize: 10.5,
            height: 1.35,
            fontWeight: FontWeight.w300,
          ),
        ),
      ],
    );
  }

  Widget _modelRow(
    ModelCategory category,
    AppPalette palette,
    ModelOption? active,
    bool busy,
    bool hasKey,
  ) {
    final provider = _drafts[category]!;
    final matching = active != null && active.provider == provider;
    return GestureDetector(
      onTap: busy ? null : () => _openModels(category),
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: palette.inputFill.withValues(alpha: 0.73),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: palette.inputBorder.withValues(alpha: 0.28),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            Icon(Icons.memory_rounded, size: 16, color: palette.textSecondary),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                matching ? active.name : state.t('chooseModel'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: matching ? palette.textPrimary : palette.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            if (busy)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  color: palette.textSecondary,
                ),
              )
            else ...[
              GestureDetector(
                onTap: () {
                  _keys[category]!.text = state.keyFor(provider) ?? '';
                  setState(() {
                    _editingKey[category] = true;
                    _catalogs.remove(category);
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.key_rounded,
                    size: 16,
                    color: palette.textSecondary,
                  ),
                ),
              ),
              Tooltip(
                message: state.t('deleteKey'),
                child: GestureDetector(
                  onTap: () => _deleteKey(category),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.delete_outline_rounded,
                      size: 17,
                      color: palette.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.expand_more_rounded,
                size: 19,
                color: palette.textSecondary,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _keyRow(
    ModelCategory category,
    AppPalette palette,
    bool busy,
    bool hasKey,
  ) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 38,
            decoration: BoxDecoration(
              color: palette.inputFill.withValues(alpha: 0.73),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: palette.inputBorder.withValues(alpha: 0.28),
              ),
            ),
            padding: const EdgeInsets.only(left: 12, right: 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _keys[category],
                    obscureText: _obscure[category] ?? true,
                    enabled: !busy,
                    onSubmitted: (_) => _connect(category),
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                    decoration: InputDecoration(
                      hintText: state.t('enterKey'),
                      hintStyle: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 14,
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 19,
                  onPressed: () => setState(
                    () => _obscure[category] = !(_obscure[category] ?? true),
                  ),
                  icon: Icon(
                    (_obscure[category] ?? true)
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: palette.textSecondary,
                    size: 19,
                  ),
                ),
                if (hasKey)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    tooltip: state.t('deleteKey'),
                    onPressed: busy ? null : () => _deleteKey(category),
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      color: palette.textSecondary,
                      size: 18,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: busy ? null : () => _connect(category),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: palette.providerActive,
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(
                  color: palette.shadow.withValues(alpha: 0.18),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: busy
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.8,
                        color: palette.providerActiveForeground,
                      ),
                    )
                  : Icon(
                      Icons.check_rounded,
                      size: 23,
                      color: palette.providerActiveForeground,
                    ),
            ),
          ),
        ),
      ],
    );
  }
}
