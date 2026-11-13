import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/theme/thmr_theme.dart';
import 'thmr_panel.dart';

Future<void> showInputHelp(BuildContext context) => showDialog<void>(
      context: context,
      builder: (_) => const InputHelpDialog(),
    );

/// Settings entry, in its own section near the bottom of the page.
class InputHelpCard extends StatelessWidget {
  const InputHelpCard({super.key});

  @override
  Widget build(BuildContext context) => ThmrPanel(
        onTap: () => showInputHelp(context),
        child: Row(children: [
          const SizedBox(
            width: 20,
            child: InputPromptGroup(
                glyphs: ['keyboard_f1_outline'],
                label: 'F1',
                iconSize: 20,
                maxIconSize: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('键盘与手柄操作', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text('查看导航、播放与音量控制的按键说明',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Theme.of(context).thmr.mutedInk)),
              ],
            ),
          ),
        ]),
      );
}

class InputHelpDialog extends StatefulWidget {
  const InputHelpDialog({super.key});

  @override
  State<InputHelpDialog> createState() => _InputHelpDialogState();
}

class _InputHelpDialogState extends State<InputHelpDialog> {
  bool _gamepad = false;

  @override
  Widget build(BuildContext context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: SizedBox(
          width: 680,
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('键盘与手柄操作',
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 16),
                        SegmentedButton<bool>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(value: false, label: Text('键盘')),
                            ButtonSegment(value: true, label: Text('手柄')),
                          ],
                          selected: {_gamepad},
                          onSelectionChanged: (value) =>
                              setState(() => _gamepad = value.single),
                        ),
                      ]),
                ),
                const Divider(height: 1),
                Flexible(
                  child: SingleChildScrollView(
                    key: ValueKey(_gamepad),
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                    child: InputHelpLegend(gamepad: _gamepad),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('关闭')),
                  ),
                ),
              ]),
        ),
      );
}

class InputHelpLegend extends StatelessWidget {
  const InputHelpLegend({super.key, required this.gamepad});
  final bool gamepad;

  @override
  Widget build(BuildContext context) {
    final mac = defaultTargetPlatform == TargetPlatform.macOS;
    final windows = defaultTargetPlatform == TargetPlatform.windows;
    final modifier = mac ? 'keyboard_command_outline' : 'keyboard_ctrl_outline';
    final name = mac ? 'Command' : 'Ctrl';
    final rows = gamepad
        ? const <_HelpBinding>[
            _HelpBinding('move', ['xbox_dpad', '/', 'xbox_stick_l'], '十字键或左摇杆',
                '按方向移动焦点'),
            _HelpBinding(
                'activate',
                ['xbox_button_a', '/', 'playstation_button_cross'],
                'A 或叉键',
                '确认，操作选中的控件'),
            _HelpBinding(
                'back',
                ['xbox_button_b', '/', 'playstation_button_circle'],
                'B 或圆圈键',
                '关闭可取消的弹窗或返回'),
            _HelpBinding(
                'play',
                ['xbox_button_x', '/', 'playstation_button_square'],
                'X 或方块键',
                '播放 / 暂停'),
            _HelpBinding(
                'search',
                ['xbox_button_y', '/', 'playstation_button_triangle'],
                'Y 或三角键',
                '打开曲库并定位搜索框'),
            _HelpBinding('previous', ['xbox_lb', '/', 'playstation_trigger_l1'],
                'LB 或 L1', '上一个主页面'),
            _HelpBinding('next', ['xbox_rb', '/', 'playstation_trigger_r1'],
                'RB 或 R1', '下一个主页面'),
            _HelpBinding(
                'scroll', ['xbox_stick_r_vertical'], '右摇杆上下', '滚动当前区域'),
            _HelpBinding('mute', ['xbox_stick_r_press'], '按下右摇杆', '静音 / 恢复音量'),
            _HelpBinding(
                'help',
                ['xbox_button_menu', '/', 'playstation4_button_options'],
                'Menu 或 Options',
                '打开操作说明'),
          ]
        : <_HelpBinding>[
            const _HelpBinding(
                'next', ['keyboard_tab_outline'], 'Tab', '下一个控件'),
            const _HelpBinding(
                'previous',
                ['keyboard_shift_outline', '+', 'keyboard_tab_outline'],
                'Shift 加 Tab',
                '上一个控件'),
            const _HelpBinding(
                'move', ['keyboard_arrows'], '方向键', '移动焦点；在音量滑杆上调整音量'),
            const _HelpBinding(
                'activate',
                ['keyboard_enter_outline', '/', 'keyboard_space_outline'],
                'Enter 或空格',
                '操作选中的按钮'),
            _HelpBinding(
                'pages',
                [
                  modifier,
                  '+',
                  'keyboard_1_outline',
                  '–',
                  'keyboard_4_outline'
                ],
                '$name 加 1 到 4',
                '依次切换收听、曲库、收藏、我的'),
            _HelpBinding('search', [modifier, '+', 'keyboard_f_outline'],
                '$name 加 F', '打开曲库并定位搜索框'),
            _HelpBinding('play', [modifier, '+', 'keyboard_p_outline'],
                '$name 加 P', '播放 / 暂停'),
            _HelpBinding(
                'mute',
                [
                  modifier,
                  '+',
                  if (mac) ...['keyboard_shift_outline', '+'],
                  'keyboard_m_outline'
                ],
                '$name ${mac ? '加 Shift ' : ''}加 M',
                '静音 / 恢复音量'),
            _HelpBinding(
                'volume',
                [
                  modifier,
                  '+',
                  'keyboard_arrow_up_outline',
                  '/',
                  'keyboard_arrow_down_outline'
                ],
                '$name 加上或下方向键',
                '音量增加 / 减少 5%'),
            if (windows)
              const _HelpBinding(
                  'mini',
                  [
                    'keyboard_ctrl_outline',
                    '+',
                    'keyboard_shift_outline',
                    '+',
                    'keyboard_m_outline'
                  ],
                  'Ctrl 加 Shift 加 M',
                  '切换迷你播放器'),
            const _HelpBinding('back', ['keyboard_escape_outline'], 'Esc',
                '关闭可取消的弹窗或返回；迷你模式下恢复主窗口'),
            const _HelpBinding(
                'limits',
                ['keyboard_home_outline', '/', 'keyboard_end_outline'],
                'Home 或 End',
                '音量滑杆获得焦点时，设为 0% / 100%'),
            const _HelpBinding('help', ['keyboard_f1_outline'], 'F1', '打开操作说明'),
          ];
    return LayoutBuilder(builder: (context, constraints) {
      final promptWidth = (constraints.maxWidth * 0.44).clamp(100.0, 204.0);
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < rows.length; i++) ...[
          _InputHelpRow(binding: rows[i], promptWidth: promptWidth),
          if (i < rows.length - 1)
            Divider(height: 1, color: Theme.of(context).thmr.panelBorder),
        ],
        const SizedBox(height: 16),
        Text(
          gamepad
              ? '音量滑杆获得焦点后，左右调整音量，上下离开滑杆。文字输入使用键盘或系统输入法。'
              : mac
                  ? '保留 ⌘+M 的系统最小化功能。普通文字输入和输入法快捷键按控件默认方式工作。'
                  : '普通文字输入和输入法快捷键按控件默认方式工作。',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Theme.of(context).thmr.mutedInk),
        ),
      ]);
    });
  }
}

class _HelpBinding {
  const _HelpBinding(this.id, this.glyphs, this.keys, this.description);
  final String id;
  final List<String> glyphs;
  final String keys;
  final String description;
}

class _InputHelpRow extends StatelessWidget {
  const _InputHelpRow({required this.binding, required this.promptWidth});
  final _HelpBinding binding;
  final double promptWidth;

  @override
  Widget build(BuildContext context) => MergeSemantics(
        child: Padding(
          key: ValueKey('input-help-${binding.id}'),
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            SizedBox(
              width: promptWidth,
              child:
                  InputPromptGroup(glyphs: binding.glyphs, label: binding.keys),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Text(binding.description,
                  textAlign: TextAlign.start,
                  style: Theme.of(context).textTheme.bodyMedium),
            ),
          ]),
        ),
      );
}

/// Center the complete chord in its column, including wrapped modifiers.
/// SVGs expose one spoken key sequence instead of individual image nodes.
class InputPromptGroup extends StatelessWidget {
  const InputPromptGroup(
      {super.key,
      required this.glyphs,
      required this.label,
      this.iconSize = 24,
      this.maxIconSize = 32});
  final List<String> glyphs;
  final String label;
  final double iconSize;
  final double maxIconSize;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.textScalerOf(context)
        .scale(iconSize)
        .clamp(iconSize, maxIconSize);
    final color = Theme.of(context).colorScheme.onSurface;
    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: Center(
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 5,
            runSpacing: 5,
            children: [
              for (final glyph in glyphs)
                if (glyph == '+' || glyph == '/' || glyph == '–')
                  Text(glyph, style: Theme.of(context).textTheme.bodySmall)
                else
                  SvgPicture.asset('assets/input_prompts/$glyph.svg',
                      height: size,
                      alignment: Alignment.center,
                      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                      excludeFromSemantics: true),
            ],
          ),
        ),
      ),
    );
  }
}
