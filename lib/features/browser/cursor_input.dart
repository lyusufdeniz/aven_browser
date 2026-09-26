part of 'browser_page.dart';

/// D-pad cursor ticker, activate/tap, and fullscreen pointer.
mixin _CursorInput on _BrowserPageBase {
  void _bumpCursor() {
    if (!mounted) return;
    if (!_cursorVisible.value) _cursorVisible.value = true;
    _cursorHide?.cancel();
    // Auto-hide only while a page player is in fullscreen.
    if (_fullscreenVideo == null) return;
    _cursorHide = Timer(const Duration(milliseconds: 2800), () {
      if (!mounted || _fullscreenVideo == null) return;
      _cursorVisible.value = false;
    });
  }

  /// Clears stuck D-pad state that survives route pushes (player open/close).
  @override
  void _resetPointerState() {
    for (final timer in _arrowRelease.values) {
      timer.cancel();
    }
    _arrowRelease.clear();
    _held.clear();
    _direction = Offset.zero;
    _tickWall = null;
    _moveStartedAt = null;
    if (_ticker.isActive) _ticker.stop();
    if (_cursorLook.value != _CursorLook.normal) {
      _cursorLook.value = _CursorLook.normal;
    }
  }

  void _onTick(Duration elapsed) {
    final now = DateTime.now();
    // Wall-clock dt stays steady even when vsync hitches after the player.
    final dt = _tickWall == null
        ? (1 / 60)
        : (now.difference(_tickWall!).inMicroseconds / 1000000).clamp(0.0, 1 / 30);
    _tickWall = now;
    if (_direction == Offset.zero ||
        _webSize.isEmpty ||
        _menuOpen ||
        _onStart ||
        _openingVideo ||
        _pageError != null) {
      if (_ticker.isActive) _ticker.stop();
      _tickWall = null;
      _moveStartedAt = null;
      if (_cursorLook.value != _CursorLook.normal) {
        _cursorLook.value = _CursorLook.normal;
      }
      return;
    }
    // Keep the hot-spot inside the drawable area (elementFromPoint needs this).
    final maxX = (_webSize.width - 1).clamp(0.0, double.infinity);
    final maxY = (_webSize.height - 1).clamp(0.0, double.infinity);
    final holdMs = _moveStartedAt == null
        ? 0
        : now.difference(_moveStartedAt!).inMilliseconds;
    // Short taps stay precise; long holds ramp up for crossing the screen.
    final t = (holdMs / 650).clamp(0.0, 1.0);
    final speed = _BrowserPageBase.cursorSpeedMin +
        (_BrowserPageBase.cursorSpeedMax - _BrowserPageBase.cursorSpeedMin) *
            t *
            t;
    final current = _cursor.value;
    var next = current + _direction * speed * dt;
    var scrollX = 0.0;
    var scrollY = 0.0;
    if (next.dx < 0) {
      scrollX = next.dx;
      next = Offset(0, next.dy);
    } else if (next.dx > maxX) {
      scrollX = next.dx - maxX;
      next = Offset(maxX, next.dy);
    }
    if (next.dy < 0) {
      scrollY = next.dy;
      next = Offset(next.dx, 0);
    } else if (next.dy > maxY) {
      scrollY = next.dy - maxY;
      next = Offset(next.dx, maxY);
    }
    next = Offset(
      next.dx.clamp(0.0, maxX),
      next.dy.clamp(0.0, maxY),
    );
    if (next != current) {
      _cursor.value = next;
      _bumpCursor();
    }
    final look = scrollY < 0
        ? _CursorLook.up
        : scrollY > 0
            ? _CursorLook.down
            : scrollX < 0
                ? _CursorLook.left
                : scrollX > 0
                    ? _CursorLook.right
                    : _CursorLook.normal;
    if (_cursorLook.value != look) _cursorLook.value = look;
    if (scrollX != 0 || scrollY != 0) {
      if (now.difference(_lastScroll).inMilliseconds > 55) {
        _lastScroll = now;
        final step = holdMs > 400 ? 22.0 : 14.0;
        _scrollBy(scrollX.sign * step, scrollY.sign * step, next.dx, next.dy);
      }
    }
  }

  void _syncDirection() {
    var x = 0.0;
    var y = 0.0;
    if (_held.contains(LogicalKeyboardKey.arrowLeft)) x -= 1;
    if (_held.contains(LogicalKeyboardKey.arrowRight)) x += 1;
    if (_held.contains(LogicalKeyboardKey.arrowUp)) y -= 1;
    if (_held.contains(LogicalKeyboardKey.arrowDown)) y += 1;
    var next = Offset(x, y);
    final length = next.distance;
    if (length > 0) next = next / length;
    if (next == _direction) return;
    final wasMoving = _direction != Offset.zero;
    _direction = next;
    if (next != Offset.zero) {
      _bumpCursor();
      if (!wasMoving) _moveStartedAt = DateTime.now();
    } else {
      _moveStartedAt = null;
    }
    if (next != Offset.zero &&
        !_ticker.isActive &&
        !_menuOpen &&
        !_onStart &&
        !_openingVideo &&
        _pageError == null) {
      _tickWall = null;
      _ticker.start();
    }
    if (next == Offset.zero && _ticker.isActive) {
      _ticker.stop();
      _tickWall = null;
    }
  }

  bool _onHardwareKey(KeyEvent event) {
    if (!mounted ||
        _onStart ||
        _menuOpen ||
        _pageTyping ||
        _pageError != null ||
        _openingVideo) {
      return false;
    }
    if (ModalRoute.of(context)?.isCurrent == false) return false;
    if (!_isArrow(event.logicalKey)) return false;
    if (!_surfaceFocus.hasFocus) {
      _surfaceFocus.canRequestFocus = true;
      _surfaceFocus.requestFocus();
    }
    _setArrow(event.logicalKey, event is! KeyUpEvent);
    return true;
  }

  void _setArrow(LogicalKeyboardKey key, bool down) {
    if (down) {
      _arrowRelease.remove(key)?.cancel();
      _held.add(key);
      _syncDirection();
      return;
    }
    // Release promptly so keys don't "stick" after the external player.
    _arrowRelease[key]?.cancel();
    _arrowRelease[key] = Timer(const Duration(milliseconds: 40), () {
      _arrowRelease.remove(key);
      _held.remove(key);
      _syncDirection();
    });
  }

  KeyEventResult _onSurfaceKey(FocusNode node, KeyEvent event) {
    if (_onStart || _pageTyping || _pageError != null) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (_isArrow(key)) {
      _setArrow(key, event is! KeyUpEvent);
      return KeyEventResult.handled;
    }
    final typed = event.character;
    if (event is KeyDownEvent && typed != null && _isTypingCharacter(typed)) {
      if (!_menuOpen) {
        setState(() => _menuOpen = true);
        _syncChrome();
      }
      final replacing = _address.text == _pageUrl;
      _address.text = replacing ? typed : '${_address.text}$typed';
      _address.selection = TextSelection.collapsed(offset: _address.text.length);
      return KeyEventResult.handled;
    }
    final activate = key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.gameButtonA;
    if (activate && event is KeyDownEvent) {
      if (_address.text.isNotEmpty && _address.text != _pageUrl) {
        _openInput(_address.text);
      } else {
        _activate();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _activate() async {
    _bumpCursor();
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final cursor = _cursor.value;
    await _input.tap(cursor.dx * pixelRatio, cursor.dy * pixelRatio);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    try {
      final result = await _controller.runJavaScriptReturningResult(_editableCheck);
      if (_jsTrue(result)) await _input.focusForTyping();
    } catch (_) {}
  }

  Future<void> _scrollBy(double dx, double dy, double x, double y) async {
    if (_webSize.isEmpty) return;
    final px = x.clamp(0.0, (_webSize.width - 1).clamp(0.0, double.infinity));
    final py = y.clamp(0.0, (_webSize.height - 1).clamp(0.0, double.infinity));
    final script = '''
(function() {
  var x = $px, y = $py, dx = $dx, dy = $dy;
  var el = document.elementFromPoint(x, y);
  while (el && el !== document.documentElement) {
    var style = getComputedStyle(el);
    var canY = (style.overflowY === 'auto' || style.overflowY === 'scroll') &&
        el.scrollHeight > el.clientHeight + 2;
    var canX = (style.overflowX === 'auto' || style.overflowX === 'scroll') &&
        el.scrollWidth > el.clientWidth + 2;
    if ((dy !== 0 && canY) || (dx !== 0 && canX)) {
      el.scrollBy(dx, dy);
      return;
    }
    el = el.parentElement;
  }
  window.scrollBy(dx, dy);
})();
''';
    try {
      await _controller.runJavaScript(script);
    } catch (_) {}
  }

  void _rememberWebSize(Size size) {
    if (size == _webSize || size.isEmpty) return;
    _webSize = size;
    final maxX = (size.width - 1).clamp(0.0, double.infinity);
    final maxY = (size.height - 1).clamp(0.0, double.infinity);
    if (!_placed) {
      _placed = true;
      _cursor.value = Offset(size.width / 2, size.height / 2);
      return;
    }
    final current = _cursor.value;
    _cursor.value = Offset(
      current.dx.clamp(0.0, maxX),
      current.dy.clamp(0.0, maxY),
    );
  }

  Offset _cursorPaintOrigin(Offset hotSpot, Size area) {
    const size = 32.0;
    final maxLeft = (area.width - size).clamp(0.0, double.infinity);
    final maxTop = (area.height - size).clamp(0.0, double.infinity);
    return Offset(
      (hotSpot.dx - size / 2).clamp(0.0, maxLeft),
      (hotSpot.dy - size / 2).clamp(0.0, maxTop),
    );
  }
}

