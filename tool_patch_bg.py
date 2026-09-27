# global background + custom title bar patch
import re

# 1) app.dart: builder-level shared background
p = 'lib/app.dart'
s = open(p, encoding='utf-8').read()
s = s.replace("import 'package:flutter/material.dart';",
"import 'dart:io' show Platform;\n\nimport 'package:flutter/foundation.dart' show kIsWeb;\nimport 'package:flutter/material.dart';\nimport 'package:window_manager/window_manager.dart';")
s = s.replace("import 'features/shell/home_shell.dart';",
"import 'features/shell/home_shell.dart';\nimport 'shared/widgets/desktop_title_bar.dart';\nimport 'shared/widgets/thmr_background.dart';")
s = s.replace('''      theme: ThmrTheme.light(settings.accentTheme),
      darkTheme: ThmrTheme.dark(settings.accentTheme),
      home: const HomeShell(),
    );''',
'''      theme: ThmrTheme.light(settings.accentTheme),
      darkTheme: ThmrTheme.dark(settings.accentTheme),
      // Single shared background under every route: pages stay transparent
      // and the illustration never jumps between tabs.
      builder: (context, child) => Stack(
        fit: StackFit.expand,
        children: [
          const ThmrBackground(child: SizedBox.expand()),
          if (!kIsWeb && Platform.isWindows)
            Column(
              children: [
                const DesktopTitleBar(),
                Expanded(child: child ?? const SizedBox.expand()),
              ],
            )
          else
            child ?? const SizedBox.expand(),
        ],
      ),
      home: const HomeShell(),
    );''')
open(p, 'w', encoding='utf-8').write(s)
print('app ok')

# 2) main.dart: hide native title bar before first frame
p = 'lib/main.dart'
s = open(p, encoding='utf-8').read()
s = s.replace("import 'package:flutter/material.dart';",
"import 'dart:io' show Platform;\n\nimport 'package:flutter/foundation.dart' show kIsWeb;\nimport 'package:flutter/material.dart';\nimport 'package:window_manager/window_manager.dart';")
s = s.replace('''void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 桌面 / 移动全平台播放后端(just_audio 桌面实现受限,统一 media_kit)
  MediaKit.ensureInitialized();
  runApp(const ProviderScope(child: ThmrApp()));
}''',
'''Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 桌面 / 移动全平台播放后端(just_audio 桌面实现受限,统一 media_kit)
  MediaKit.ensureInitialized();

  if (!kIsWeb && Platform.isWindows) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      titleBarStyle: TitleBarStyle.hidden,
      minimumSize: Size(430, 660),
      backgroundColor: Colors.transparent,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(const ProviderScope(child: ThmrApp()));
}''')
open(p, 'w', encoding='utf-8').write(s)
print('main ok')

# 3) desktop title bar widget
open('lib/shared/widgets/desktop_title_bar.dart', 'w', encoding='utf-8').write(
'''// Custom Windows title bar (native one hidden via window_manager).

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/theme/thmr_theme.dart';

class DesktopTitleBar extends StatelessWidget {
  const DesktopTitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).thmr;
    return Container(
      height: 38,
      color: tokens.pageBg,
      child: Row(
        children: [
          const SizedBox(width: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: Image.asset('assets/brand/logo.png',
                width: 22, height: 22),
          ),
          const SizedBox(width: 9),
          Text(
            '东方音乐电台 THMR',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: tokens.mutedInk,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const Spacer(),
          // DragToMoveArea covers the empty middle so the window can be
          // dragged by any empty spot.
          Expanded(child: DragToMoveArea(child: const SizedBox.expand())),
          _CaptionButton(
            icon: Icons.remove_rounded,
            onTap: () => windowManager.minimize(),
          ),
          _CaptionButton(
            icon: Icons.crop_square_rounded,
            onTap: () async {
              if (await windowManager.isMaximized()) {
                await windowManager.unmaximize();
              } else {
                await windowManager.maximize();
              }
            },
          ),
          _CaptionButton(
            icon: Icons.close_rounded,
            danger: true,
            onTap: () => windowManager.close(),
          ),
        ],
      ),
    );
  }
}

class _CaptionButton extends StatelessWidget {
  const _CaptionButton({required this.icon, required this.onTap, this.danger});

  final IconData icon;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).thmr;
    return SizedBox(
      width: 44,
      height: 38,
      child: InkWell(
        onTap: onTap,
        hoverColor: danger
            ? const Color(0xFFC42B1C)
            : tokens.ink.withValues(alpha: 0.06),
        child: Icon(
          icon,
          size: 16,
          color: danger
              ? tokens.mutedInk
              : tokens.mutedInk,
        ),
      ),
    );
  }
}
''')
print('title bar ok')

# 4) strip per-page backgrounds (pages become transparent, global bg shows)
# 4a. listen_screen: two layouts drop ThmrBackground wrapper
p = 'lib/features/listen/listen_screen.dart'
s = open(p, encoding='utf-8').read()
s = s.replace("import '../../shared/widgets/thmr_background.dart';\n", "")
s = s.replace("""    return ThmrBackground(
      child: SafeArea(
        bottom: false,
        child: LayoutBuilder(builder: (context, c) {""",
"""    return SafeArea(
        bottom: false,
        child: LayoutBuilder(builder: (context, c) {""")
s = s.replace("""          return content;
        }),
      ),
    );
  }
}""",
"""          return content;
        }),
    );
  }
}""")
open(p, 'w', encoding='utf-8').write(s)
print('listen ok')

# 4b. library_screen
p = 'lib/features/library/library_screen.dart'
s = open(p, encoding='utf-8').read()
s = s.replace("import '../../shared/widgets/thmr_background.dart';\n", "")
s = s.replace("""    return ThmrBackground(
      child: SafeArea(
        child: Padding(""",
"""    return SafeArea(
        child: Padding(""")
s = s.replace("""          ),
        ),
      ),
    );
  }
}

class _LibraryTile extends ConsumerWidget {""",
"""          ),
        ),
    );
  }
}

class _LibraryTile extends ConsumerWidget {""")
open(p, 'w', encoding='utf-8').write(s)
print('library ok')

# 4c. collections_screen (list page only; detail keeps its own wrapper removed too)
p = 'lib/features/collections/collections_screen.dart'
s = open(p, encoding='utf-8').read()
s = s.replace("import '../../shared/widgets/thmr_background.dart';\n", "")
s = s.replace("""    return ThmrBackground(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: '查看他人分享',""",
"""    return SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: '查看他人分享',""")
open(p, 'w', encoding='utf-8').write(s)
print('collections list ok')

# 4d. account_screen
p = 'lib/features/account/account_screen.dart'
s = open(p, encoding='utf-8').read()
s = s.replace("import '../../shared/widgets/thmr_background.dart';\n", "")
s = s.replace("""    return ThmrBackground(
      child: SafeArea(
        child: ListView(""",
"""    return SafeArea(
        child: ListView(""")
open(p, 'w', encoding='utf-8').write(s)
print('account ok')

# 4e. collection detail (already transparent scaffold w/ own bg) -> drop wrapper
p = 'lib/features/collections/collections_screen.dart'
s = open(p, encoding='utf-8').read()
s = s.replace("""    return ThmrBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(""",
"""    return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(""")
open(p, 'w', encoding='utf-8').write(s)
print('detail ok')

# 4f. shared collection screen: transparent scaffold (global bg behind)
p = 'lib/features/collections/shared_collection_screen.dart'
s = open(p, encoding='utf-8').read()
s = s.replace("      backgroundColor: tokens.pageBg,", "      backgroundColor: Colors.transparent,")
open(p, 'w', encoding='utf-8').write(s)
print('shared ok')

# 4g. queue page/sheet content: QueueSheet opaque (fine), nothing to change
print('ALL PATCHED')
