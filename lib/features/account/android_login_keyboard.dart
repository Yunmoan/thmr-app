import 'package:flutter_inappwebview/flutter_inappwebview.dart';

Future<void> updateAndroidLoginKeyboard(
    InAppWebViewController controller, double insetPixels) async {
  try {
    await controller.evaluateJavascript(
        source: '$_scrollForKeyboard($insetPixels);');
  } catch (_) {
    // 页面切换或关闭时，原生 WebView 可能已不可用。
  }
}

// Chromium 139 开始自行调整可视视口。旧版在页面末尾留出滚动空间来避开键盘。
const _scrollForKeyboard = r'''
(insetPixels => {
  const chrome = /Chrome\/(\d+)/.exec(navigator.userAgent);
  if ((chrome && Number(chrome[1]) >= 139) || !document.body) return;

  const id = 'thmr-android-keyboard-spacer';
  let spacer = document.getElementById(id);
  if (!insetPixels) {
    if (spacer) {
      document.removeEventListener('focusin', spacer.revealFocusedInput);
      spacer.remove();
    }
    return;
  }

  if (!spacer) {
    spacer = document.createElement('div');
    spacer.id = id;
    spacer.setAttribute('aria-hidden', 'true');
    spacer.style.cssText = 'position: absolute; left: 0; width: 1px; pointer-events: none';
    spacer.style.top = (document.scrollingElement || document.documentElement).scrollHeight + 'px';
    document.documentElement.appendChild(spacer);

    spacer.revealFocusedInput = () => {
      const field = document.activeElement;
      if (!field || !field.matches('input, textarea, [contenteditable]')) return;
      const viewport = window.visualViewport;
      const visibleTop = viewport ? viewport.offsetTop : 0;
      const visibleBottom = visibleTop + (viewport ? viewport.height : window.innerHeight)
        - parseFloat(spacer.style.height);
      const rect = field.getBoundingClientRect();
      const above = rect.top - visibleTop - 12;
      const below = rect.bottom - visibleBottom + 12;
      if (above < 0) window.scrollBy(0, above);
      else if (below > 0) window.scrollBy(0, below);
    };
    document.addEventListener('focusin', spacer.revealFocusedInput);
  }

  const viewport = window.visualViewport;
  const scale = viewport ? viewport.scale : 1;
  spacer.style.height = insetPixels / (window.devicePixelRatio * scale) + 'px';
  spacer.revealFocusedInput();
})
''';
