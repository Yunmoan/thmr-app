import 'package:flutter/cupertino.dart' show CupertinoButton;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsRole;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/mobile_presentation.dart';
import '../../core/theme/thmr_motion.dart';
import '../../core/theme/thmr_theme.dart';
import 'focus_outline.dart';

class ThmrMenuButton<T> extends ConsumerWidget {
  const ThmrMenuButton({
    super.key,
    required this.tooltip,
    required this.itemBuilder,
    required this.onSelected,
    this.initialValue,
    this.enabled = true,
    this.child,
    this.icon,
    this.position,
  }) : assert((child == null) != (icon == null));

  final String tooltip;
  final List<PopupMenuItem<T>> Function(BuildContext) itemBuilder;
  final ValueChanged<T> onSelected;
  final T? initialValue;
  final bool enabled;
  final Widget? child;
  final Widget? icon;
  final PopupMenuPosition? position;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ios = hasIosPresentation;
    final theme = Theme.of(context);
    if (ios && usesPhoneLayout(context, ref)) {
      return FocusOutline(
        radius: 10,
        child: Tooltip(
          message: tooltip,
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size.square(44),
            foregroundColor: theme.thmr.ink,
            pressedOpacity: .65,
            onPressed: !enabled
                ? null
                : () async {
                    final items = itemBuilder(context);
                    if (items.isEmpty) return;
                    final value = await _showPhoneMenu(
                      context,
                      tooltip,
                      _iosItems(context, items, initialValue),
                    );
                    if (value != null && context.mounted) onSelected(value);
                  },
            child: child ?? icon!,
          ),
        ),
      );
    }

    return PopupMenuButton<T>(
      tooltip: tooltip,
      itemBuilder: (context) {
        final items = itemBuilder(context);
        return ios ? _iosItems(context, items, initialValue) : items;
      },
      initialValue: initialValue,
      enabled: enabled,
      onSelected: onSelected,
      popUpAnimationStyle: ThmrMotion.menuStyle(context),
      position: ios ? PopupMenuPosition.under : position,
      offset: ios ? const Offset(0, 4) : Offset.zero,
      constraints: ios ? _padMenuWidth : null,
      shape: ios ? _iosMenuShape(theme) : null,
      menuPadding: ios ? const EdgeInsets.symmetric(vertical: 6) : null,
      clipBehavior: ios ? Clip.antiAlias : Clip.none,
      requestFocus: ios ? true : null,
      icon: icon,
      child: child,
    );
  }
}

/// 从现有自定义控件打开同一套菜单。
Future<T?> showThmrMenu<T>({
  required BuildContext context,
  required WidgetRef ref,
  required String label,
  required List<PopupMenuItem<T>> items,
}) {
  final ios = hasIosPresentation;
  final theme = Theme.of(context);
  final menuItems = ios ? _iosItems<T>(context, items, null) : items;
  if (ios && usesPhoneLayout(context, ref, listen: false)) {
    return _showPhoneMenu(context, label, menuItems);
  }
  final overlay = Navigator.of(context).overlay!.context.findRenderObject();
  RelativeRect? position;
  return showMenu<T>(
    context: context,
    semanticLabel: label,
    popUpAnimationStyle: ThmrMotion.menuStyle(context),
    constraints: ios ? _padMenuWidth : null,
    shape: ios ? _iosMenuShape(theme) : null,
    menuPadding: ios ? const EdgeInsets.symmetric(vertical: 6) : null,
    clipBehavior: ios ? Clip.antiAlias : Clip.none,
    requestFocus: ios ? true : null,
    positionBuilder: (_, constraints) {
      final anchor = context.mounted ? context.findRenderObject() : null;
      if (anchor is RenderBox && anchor.attached && anchor.hasSize) {
        final bounds = anchor.localToGlobal(
              Offset(0, anchor.size.height + 4),
              ancestor: overlay,
            ) &
            Size(anchor.size.width, 0);
        position = RelativeRect.fromSize(bounds, constraints.biggest);
      }
      return position ?? RelativeRect.fill;
    },
    items: menuItems,
  );
}

const _padMenuWidth = BoxConstraints(minWidth: 184, maxWidth: 312);

RoundedRectangleBorder _iosMenuShape(ThemeData theme) => RoundedRectangleBorder(
      side: BorderSide(color: theme.thmr.panelBorder),
      borderRadius: BorderRadius.circular(16),
    );

List<PopupMenuItem<T>> _iosItems<T>(
  BuildContext context,
  List<PopupMenuItem<T>> items,
  T? initialValue,
) {
  final theme = Theme.of(context);
  final tokens = theme.thmr;
  final accent = theme.colorScheme.primary;
  return [
    for (final item in items)
      PopupMenuItem<T>(
        key: item.key,
        value: item.value,
        enabled: item.enabled,
        onTap: item.onTap,
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        labelTextStyle: WidgetStatePropertyAll(TextStyle(
          fontSize: 16,
          height: 1.2,
          color: item.enabled ? tokens.ink : theme.disabledColor,
        )),
        child: Semantics(
          selected: initialValue == null ? null : initialValue == item.value,
          child: Row(
            spacing: 12,
            children: [
              Expanded(child: item.child ?? const SizedBox.shrink()),
              if (initialValue != null)
                SizedBox.square(
                  dimension: 18,
                  child: item.value == initialValue
                      ? Icon(Icons.check_rounded, size: 18, color: accent)
                      : null,
                ),
            ],
          ),
        ),
      ),
  ];
}

Future<T?> _showPhoneMenu<T>(
  BuildContext context,
  String label,
  List<PopupMenuItem<T>> items,
) {
  final theme = Theme.of(context);
  final tokens = theme.thmr;
  return showModalBottomSheet<T>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    requestFocus: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black38,
    showDragHandle: false,
    sheetAnimationStyle: ThmrMotion.style(context),
    constraints: const BoxConstraints(maxWidth: 460),
    builder: (context) => SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Theme(
        data: theme.copyWith(
          splashFactory: NoSplash.splashFactory,
          highlightColor: tokens.accentSoft,
        ),
        child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .86,
            ),
            child: Material(
              color: tokens.solidPanel,
              shape: _iosMenuShape(theme),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 16, right: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Semantics(
                            header: true,
                            child: Text(
                              label,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '关闭菜单',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded, size: 20),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: tokens.panelBorder),
                  Flexible(
                    child: Semantics(
                      container: true,
                      explicitChildNodes: true,
                      role: SemanticsRole.menu,
                      child: ListView.separated(
                        primary: false,
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: items.length,
                        itemBuilder: (_, index) => items[index],
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          indent: 16,
                          endIndent: 16,
                          color: tokens.panelBorder,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )),
      ),
    ),
  );
}
