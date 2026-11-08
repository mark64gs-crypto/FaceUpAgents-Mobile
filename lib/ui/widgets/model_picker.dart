import 'package:flutter/material.dart';

import '../../core/app_strings.dart';
import '../../core/app_theme.dart';
import '../../core/models.dart';

Future<ModelOption?> showModelPicker(
  BuildContext context, {
  required AppStrings strings,
  required ConnectResult result,
  ModelOption? current,
}) {
  return showModalBottomSheet<ModelOption>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) =>
        _ModelPickerSheet(strings: strings, result: result, current: current),
  );
}

class _ModelPickerSheet extends StatefulWidget {
  const _ModelPickerSheet({
    required this.strings,
    required this.result,
    this.current,
  });

  final AppStrings strings;
  final ConnectResult result;
  final ModelOption? current;

  @override
  State<_ModelPickerSheet> createState() => _ModelPickerSheetState();
}

class _ModelPickerSheetState extends State<_ModelPickerSheet> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final query = _search.text.trim().toLowerCase();
    final models = widget.result.models
        .where(
          (model) =>
              query.isEmpty ||
              model.name.toLowerCase().contains(query) ||
              model.id.toLowerCase().contains(query) ||
              (model.description ?? '').toLowerCase().contains(query),
        )
        .toList(growable: false);
    return FractionallySizedBox(
      heightFactor: 0.82,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.textSecondary.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.strings.t('modelsTitle'),
                    style: AppTypography.settingsLabel.copyWith(
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    height: 42,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: palette.settingsRow,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.search_rounded,
                          size: 20,
                          color: palette.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _search,
                            onChanged: (_) => setState(() {}),
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontSize: 14,
                            ),
                            decoration: InputDecoration(
                              hintText: widget.strings.t('modelSearchHint'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            Expanded(
              child: models.isEmpty
                  ? Center(
                      child: Text(
                        widget.strings.t('noModelsFound'),
                        style: AppTypography.body.copyWith(
                          color: palette.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
                      itemCount: models.length,
                      separatorBuilder: (_, _) =>
                          Divider(height: 1, color: palette.divider),
                      itemBuilder: (context, index) {
                        final model = models[index];
                        final selected =
                            widget.current?.id == model.id &&
                            widget.current?.provider == model.provider;
                        return InkWell(
                          onTap: () => Navigator.of(context).pop(model),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        model.name,
                                        style: TextStyle(
                                          color: palette.textPrimary,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        model.id,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: palette.textSecondary,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                if (selected)
                                  Icon(
                                    Icons.check_circle_rounded,
                                    size: 22,
                                    color: palette.textPrimary,
                                  )
                                else
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    size: 22,
                                    color: palette.textSecondary,
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
