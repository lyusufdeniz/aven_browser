part of 'browser_page.dart';

/// Page lifecycle, error/retry, and WebView suspend/resume.
mixin _BrowserNavigation on _BrowserPageBase {
  void _onPageStarted(String url) {
    _mediaEpoch++;
    _progress.value = 8;
    _pageLoading.value = true;
    _loadTimeout?.cancel();
    _loadTimeout = Timer(const Duration(seconds: 10), () {
      if (!mounted) return;
      _pageLoading.value = false;
      if (_progress.value < 100) _progress.value = 100;
    });
    setState(() {
      _pageUrl = url;
      _pageError = null;
      if (isAvenWebUrl(url)) {
        _onStart = false;
        _address.text = url;
      }
      _saved = _bookmarks.any((item) => item.url == url);
    });
    if (isAvenWebUrl(url) && _webSuspended) {
      unawaited(_resumeWebPage());
    }
    // Lightweight reset only — do not inject calm/MutationObserver while the
    // document is still parsing sync scripts (deadlocks TV WebView loads).
    unawaited(
      _controller.runJavaScript(
        'window.__avenPool=[];window.__avenWantPlay=false;window.__avenLastPayload=null;window.__avenArmedPlay=false;',
      ),
    );
    _input.watchMedia();
  }

  bool _sameDocument(String? a, String? b) {
    if (a == null || b == null || a.isEmpty || b.isEmpty) return false;
    Uri? left = Uri.tryParse(a);
    Uri? right = Uri.tryParse(b);
    if (left == null || right == null) return a == b;
    return left.replace(fragment: '').toString() == right.replace(fragment: '').toString();
  }

  Future<void> _onPageFinished(String url) async {
    _loadTimeout?.cancel();
    _pageLoading.value = false;
    _progress.value = 100;
    if (!_addressEditing) {
      await _input.prepareForInput();
    }
    await _installHooks();
    await _installBannerCss();
    if (_lite) await _installLiteCss();
    if (_adBlock != AdBlock.off) await _installAdblockCss();
    await _installMediaSiteHints();
    await _input.watchMedia();
    final title = await _controller.getTitle();
    final back = await _controller.canGoBack();
    final forward = await _controller.canGoForward();
    if (!mounted) return;
    final label = (title == null || title.trim().isEmpty) ? url : title.trim();
    if (isAvenWebUrl(url) && _pageError == null) {
      await _store.addHistory(
        WebLink(title: label, url: url, savedAt: DateTime.now().millisecondsSinceEpoch),
      );
    }
    if (!mounted) return;
    setState(() {
      _pageUrl = url;
      _pageTitle = label;
      _canBack = back;
      _canForward = forward;
      if (isAvenWebUrl(url) && !_addressEditing) _address.text = url;
      _saved = _bookmarks.any((item) => item.url == url);
      if (isAvenWebUrl(url)) _onStart = false;
    });
    _wakeSurface();
  }

  void _onError(WebResourceError error) {
    if (error.isForMainFrame != true || !mounted) return;
    _loadTimeout?.cancel();
    _pageLoading.value = false;
    _progress.value = 100;
    _holdSurfaceForError();
    setState(() {
      _pageError = _PageError.fromResource(error);
    });
  }

  void _onHttpError(HttpResponseError error) {
    if (!mounted) return;
    final code = error.response?.statusCode;
    if (code == null || code < 400) return;
    final uri = error.response?.uri ?? error.request?.uri;
    final url = uri?.toString();
    if (url == null) return;
    final current = _pageUrl ?? _address.text;
    if (!_sameDocument(url, current)) return;
    _loadTimeout?.cancel();
    _pageLoading.value = false;
    _progress.value = 100;
    _holdSurfaceForError();
    setState(() {
      _pageError = _PageError.fromHttp(code, url);
    });
  }

  void _holdSurfaceForError() {
    _resetPointerState();
    _surfaceFocus.canRequestFocus = false;
    _surfaceFocus.unfocus();
    _addressFocus.unfocus();
  }

  void _retryPage() {
    final url = _pageError?.url ?? _pageUrl ?? _address.text;
    setState(() => _pageError = null);
    _surfaceFocus.canRequestFocus = true;
    if (isAvenWebUrl(url)) {
      _controller.loadRequest(Uri.parse(url));
    } else {
      _controller.reload();
    }
  }

  @override
  void didChangeMetrics() {
    _wakeTimer?.cancel();
    _wakeTimer = Timer(const Duration(milliseconds: 60), () {
      if (mounted) _wakeSurface();
    });
  }

  Future<void> _wakeSurface() async {
    await _input.refreshSurface();
    if (!mounted) return;
    _surfaceKick.value = 1;
    final origin = _cursor.value;
    _cursor.value = origin + const Offset(0.4, 0);
    await Future<void>.delayed(const Duration(milliseconds: 48));
    if (!mounted) return;
    _cursor.value = origin;
    _surfaceKick.value = 0;
    await _input.refreshSurface();
  }

  /// Keeps the last document loaded but stops media and freezes the WebView
  /// so home / chrome overlays do not leave audio playing underneath.
  Future<void> _suspendWebPage() async {
    _mediaEpoch++;
    _webSuspended = true;
    try {
      await _controller.runJavaScript(r'''
(function(){
  window.__avenWantPlay = false;
  window.__avenLastPayload = null;
  try { window.__avenPool = []; } catch(e) {}
  function kill(v){
    try {
      v.pause();
      v.removeAttribute('autoplay');
      v.autoplay = false;
      v.muted = true;
      v.preload = 'none';
      try { v.removeAttribute('src'); v.load(); } catch(e) {}
      try {
        while (v.firstChild) v.removeChild(v.firstChild);
        v.load();
      } catch(e) {}
    } catch(e) {}
  }
  try {
    document.querySelectorAll('video,audio').forEach(kill);
  } catch(e) {}
  try {
    document.querySelectorAll('iframe').forEach(function(f){
      try {
        var d = f.contentDocument || (f.contentWindow && f.contentWindow.document);
        if (!d) return;
        d.querySelectorAll('video,audio').forEach(kill);
      } catch(e) {}
    });
  } catch(e) {}
})();
''');
    } catch (_) {}
    try {
      await _input.pauseWebView();
    } catch (_) {}
  }

  Future<void> _resumeWebPage() async {
    if (!_webSuspended) return;
    _webSuspended = false;
    try {
      await _input.resumeWebView();
    } catch (_) {}
    if (mounted && !_onStart) await _wakeSurface();
  }
}

