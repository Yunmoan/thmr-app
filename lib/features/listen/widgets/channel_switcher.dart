import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/focus_outline.dart';
import '../../../core/config.dart';
import '../../../core/models/models.dart';
import '../../../core/state/channel_provider.dart';
import '../../../core/state/settings_provider.dart';
import '../../../core/theme/thmr_theme.dart';

class ChannelSwitcher extends ConsumerWidget {
  const ChannelSwitcher({super.key, this.station});

  static const _groupPadding = EdgeInsets.fromLTRB(8, 2, 2, 2);
  static const _choicePadding = EdgeInsets.symmetric(horizontal: 8);
  static const _spacing = 4.0;
  static const _menuWidth = BoxConstraints(maxWidth: 240);
  static const _menuRowHeight = 36.0;

  final StationInfo? station;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stationId = ref.watch(activeStationIdProvider);
    final catalog = ref.watch(channelCatalogProvider);
    final channels = catalog.valueOrNull ?? const <RadioChannel>[];
    final current =
        channels.where((channel) => channel.id == stationId).firstOrNull;
    final name =
        current?.name ?? (station?.id == stationId ? station!.name : stationId);
    final canReset = catalog.hasError &&
        channels.isEmpty &&
        stationId != appConfig.stationId;
    final canOpen =
        catalog.hasError || channels.any((channel) => channel.id != stationId);
    final theme = Theme.of(context);
    final tokens = theme.thmr;
    final accent = theme.colorScheme.primary;
    final radius = BorderRadius.circular(7);
    final decoration = BoxDecoration(
      color: tokens.panelSoft,
      borderRadius: radius,
      border: Border.all(color: tokens.panelBorder),
    );
    final nameStyle =
        theme.textTheme.labelMedium!.copyWith(fontWeight: FontWeight.w600);
    final labelStyle = nameStyle.copyWith(color: tokens.mutedInk);

    void select(String id) {
      if (id != ref.read(activeStationIdProvider)) {
        ref.read(settingsProvider.notifier).selectStation(id);
      }
    }

    PopupMenuItem<String> menuItem({
      required String label,
      String? value,
      bool selected = false,
      IconData? icon,
      VoidCallback? onTap,
    }) {
      return PopupMenuItem<String>(
        key: value == null ? null : ValueKey('channel-menu-$value'),
        value: value,
        onTap: onTap,
        height: _menuRowHeight,
        padding: EdgeInsets.zero,
        child: AncestorFocusOutline(
            child: Semantics(
          selected: selected,
          child: Container(
            constraints: const BoxConstraints(minHeight: _menuRowHeight),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? tokens.accentSoft : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Row(
              spacing: 6,
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: nameStyle.copyWith(
                      color: tokens.ink,
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox.square(
                  dimension: 16,
                  child: Icon(
                    selected ? Icons.check_rounded : icon,
                    size: 16,
                    color: selected ? accent : tokens.mutedInk,
                  ),
                ),
              ],
            ),
          ),
        )),
      );
    }

    return LayoutBuilder(builder: (context, constraints) {
      if (!catalog.hasError &&
          current != null &&
          channels.length >= 2 &&
          channels.length <= 3 &&
          _inlineWidth(context, channels, nameStyle) <= constraints.maxWidth) {
        return DecoratedBox(
          decoration: decoration,
          child: Padding(
            padding: _groupPadding,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: _spacing,
              children: [
                Text('频道', style: labelStyle),
                for (final channel in channels)
                  Semantics(
                    selected: channel.id == stationId,
                    child: TextButton(
                      onPressed: () => select(channel.id),
                      style: TextButton.styleFrom(
                        textStyle: nameStyle,
                        minimumSize: const Size(0, 30),
                        padding: _choicePadding,
                        visualDensity: VisualDensity.standard,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(5)),
                        backgroundColor: channel.id == stationId
                            ? tokens.accentSoft
                            : Colors.transparent,
                        foregroundColor: channel.id == stationId
                            ? tokens.ink
                            : tokens.mutedInk,
                        overlayColor: accent,
                      ),
                      child: Text(channel.name, maxLines: 1, softWrap: false),
                    ),
                  ),
              ],
            ),
          ),
        );
      }

      final trigger = ConstrainedBox(
        constraints: _menuWidth,
        child: DecoratedBox(
          decoration: decoration,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 6,
              children: [
                Text('频道', style: labelStyle),
                Flexible(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: nameStyle,
                  ),
                ),
                if (canOpen)
                  Icon(Icons.expand_more_rounded,
                      color: tokens.mutedInk, size: 16)
                else if (catalog.isLoading)
                  const SizedBox.square(
                    dimension: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
        ),
      );
      if (!canOpen) return trigger;

      return FocusOutline(
          radius: 7,
          child: PopupMenuButton<String>(
            tooltip: '切换频道',
            position: PopupMenuPosition.under,
            offset: const Offset(0, 4),
            constraints: _menuWidth,
            menuPadding: const EdgeInsets.all(4),
            borderRadius: radius,
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: BorderSide(color: tokens.panelBorder),
            ),
            color: tokens.solidPanel,
            elevation: 3,
            shadowColor: Colors.black.withValues(alpha: 0.32),
            surfaceTintColor: Colors.transparent,
            clipBehavior: Clip.antiAlias,
            requestFocus: true,
            onSelected: select,
            itemBuilder: (context) => [
              for (final channel in channels)
                menuItem(
                  value: channel.id,
                  selected: channel.id == stationId,
                  label: channel.name,
                ),
              if (canReset)
                menuItem(
                  value: appConfig.stationId,
                  label: '恢复默认频道',
                  icon: Icons.restore_rounded,
                ),
              if (catalog.hasError)
                menuItem(
                  onTap: () => ref.invalidate(channelCatalogProvider),
                  label: '重新加载频道',
                  icon: Icons.refresh_rounded,
                ),
            ],
            child: trigger,
          ));
    });
  }

  double _inlineWidth(
      BuildContext context, List<RadioChannel> channels, TextStyle style) {
    final painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    );
    var width = _groupPadding.horizontal +
        channels.length * (_choicePadding.horizontal + _spacing);
    for (final label in ['频道', ...channels.map((channel) => channel.name)]) {
      painter.text = TextSpan(text: label, style: style);
      painter.layout();
      width += painter.width.ceilToDouble();
    }
    painter.dispose();
    return width;
  }
}
