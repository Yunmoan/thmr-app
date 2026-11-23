import 'package:flutter/material.dart';

import '../../core/theme/thmr_focus_ring.dart';

/// 焦点描边绘制在前景，即使 InkWell 的子组件绘制不透明面板也可见。
/// 它不占额外的焦点顺序或布局空间。
class FocusOutline extends StatefulWidget {
  const FocusOutline({
    super.key,
    required this.child,
    this.radius = 8,
    this.focusBounds = false,
  });
  final Widget child;
  final double radius;

  /// 使用控件实际绘制的范围作为描边边界，避开为了指针命中增加的内边距。
  final bool focusBounds;

  @override
  State<FocusOutline> createState() => _FocusOutlineState();
}

class _FocusOutlineState extends State<FocusOutline> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) => Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (focused) => setState(() => _focused = focused),
        child: ThmrFocusRing(
          focused: _focused,
          radius: widget.radius,
          focusNode: widget.focusBounds && _focused
              ? FocusManager.instance.primaryFocus
              : null,
          child: widget.child,
        ),
      );
}

/// 为菜单项和导航项等自行管理焦点的控件绘制描边。监听其现有焦点节点，不增加 Tab 停靠点。
class AncestorFocusOutline extends StatelessWidget {
  const AncestorFocusOutline({
    super.key,
    required this.child,
    this.radius = 8,
    this.outlineChild = false,
  });

  final Widget child;
  final double radius;

  /// 监听所属控件的焦点，仅描边当前的内容区域。
  final bool outlineChild;

  @override
  Widget build(BuildContext context) => ThmrFocusRing(
        focused: Focus.of(context).hasPrimaryFocus,
        focusNode: outlineChild ? null : Focus.of(context),
        radius: radius,
        child: child,
      );
}

/// 采用 Material 3 导航栏选中指示器的 56 × 32 逻辑像素尺寸，描边范围不包括标签。
class NavigationRailFocusIcon extends StatelessWidget {
  const NavigationRailFocusIcon({super.key, required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) => AncestorFocusOutline(
        outlineChild: true,
        radius: 16,
        child: SizedBox(width: 56, height: 32, child: Icon(icon)),
      );
}
