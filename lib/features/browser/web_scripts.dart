import 'dart:convert';

import 'package:webview_flutter/webview_flutter.dart';

import '../../core/adblock/ad_cosmetic.dart';

/// WebView JS injectors for calm/lite/media/ad cosmetics.
class WebScripts {
  /// Shared once: calm + lite both call these window helpers.
  static const _playerHelpersJs = r'''
(function(){
  if (window.__avenPlayerHelpers) return;
  window.__avenPlayerHelpers = true;
  window.__avenWakePlayerIframes = function(){
    var hasPlayPoster = !!document.querySelector('.play-that-video:not([hidden])');
    if (hasPlayPoster) {
      document.querySelectorAll('.play-that-video,.play-icon,.video-container').forEach(function(el){
        try {
          el.style.removeProperty('display');
          el.style.removeProperty('visibility');
          el.style.removeProperty('opacity');
          el.style.removeProperty('z-index');
          el.style.removeProperty('min-height');
          el.style.removeProperty('pointer-events');
        } catch (e0) {}
      });
      return;
    }
    var nodes = document.querySelectorAll('iframe[data-src],iframe[data-lazy-src],iframe[data-original]');
    for (var i = 0; i < nodes.length; i++) {
      var f = nodes[i];
      try {
        var ds = f.getAttribute('data-src') || f.getAttribute('data-lazy-src') || f.getAttribute('data-original') || '';
        if (!ds) continue;
        var parent = f.parentElement;
        var parentHint = parent ? ((parent.id || '') + ' ' + (parent.className || '')) : '';
        var look = (ds + ' ' + parentHint + ' ' + (f.className || '')).toLowerCase();
        var isPlayer = /embed|player|video|rapidrame|stream|fil|dizi|watch|movie|vidmo|ok\.ru|dailymotion|youtube|jwplayer|plyr/.test(look)
          || /video-container|player|embed/.test(parentHint.toLowerCase());
        if (!isPlayer) continue;
        if (!f.getAttribute('src')) f.setAttribute('src', ds);
        f.removeAttribute('loading');
        f.loading = 'eager';
      } catch (e) {}
    }
    document.querySelectorAll('.play-that-video,.play-icon,.video-container').forEach(function(el){
      try {
        el.style.removeProperty('display');
        el.style.removeProperty('visibility');
        el.style.removeProperty('opacity');
        el.style.removeProperty('z-index');
        el.style.removeProperty('min-height');
        el.style.removeProperty('pointer-events');
      } catch (e2) {}
    });
  };
  window.__avenArmSitePlayPoster = function(){
    if (window.__avenArmedPlay) return;
    var play = document.querySelector('.play-that-video:not([hidden])');
    if (!play) return;
    window.__avenArmedPlay = true;
    setTimeout(function(){
      try {
        var still = document.querySelector('.play-that-video:not([hidden])');
        if (still) still.click();
      } catch (e) {}
    }, 1200);
  };
})();
''';

  static Future<void> _ensurePlayerHelpers(WebViewController controller) async {
    await controller.runJavaScript(_playerHelpersJs);
  }

  static Future<void> installMediaSiteHints(WebViewController controller) async {
    try {
      await controller.runJavaScript(r'''
(function(){
  window.__avenMediaSite = true;
  var s = document.getElementById('aven-media-style');
  if (!s) {
    s = document.createElement('style');
    s.id = 'aven-media-style';
    (document.head || document.documentElement).appendChild(s);
  }
  // Keep players interactive; collapse chat/emote chrome that burns TV CPU.
  s.textContent = [
    'video,iframe[src*="player"],iframe[src*="youtube"],iframe[src*="kick"],',
    '.video-js,.jwplayer,[data-player],#player,.player{',
    'content-visibility:visible!important;contain:none!important;',
    'opacity:1!important;visibility:visible!important;}',
    'video{max-height:100vh!important;}',
    // Never force-display .play-that-video - after click the site sets [hidden]
    // and our !important display:block would cover the real player forever.
    '.play-that-video:not([hidden]),.play-icon{',
    'content-visibility:visible!important;contain:none!important;}',
    '.video-container[hidden]{display:none!important}',
    // Chat / reactions / emote rails - hide on leanback.
    '[class*="chatroom" i],[class*="chat-room" i],[class*="chat-panel" i],',
    '[class*="ChatRoom"],[class*="ChatPanel"],[data-testid*="chat" i],',
    '#chatroom-messages,#chatroom,[id*="chatroom" i],',
    'aside[class*="chat" i],section[class*="chat" i],',
    '[class*="emote-picker" i],[class*="emoji-picker" i],',
    '[class*="reaction-panel" i],[class*="channel-emotes" i],',
    '[class*="live-chat" i],ytd-live-chat-frame,#chat{',
    'display:none!important;visibility:hidden!important;',
    'width:0!important;max-width:0!important;height:0!important;',
    'overflow:hidden!important;pointer-events:none!important;}'
  ].join('');

  function anyPlaying(){
    var vs = document.querySelectorAll('video');
    for (var i = 0; i < vs.length; i++) {
      if (!vs[i].paused && !vs[i].ended) return true;
    }
    return false;
  }
  function reportBusy(){
    try {
      if (window.AvenBusy) AvenBusy.postMessage(anyPlaying() ? '1' : '0');
    } catch (e) {}
  }
  if (!window.__avenBusyHook) {
    window.__avenBusyHook = true;
    document.addEventListener('playing', function(ev){
      if (ev.target && ev.target.tagName === 'VIDEO') reportBusy();
    }, true);
    document.addEventListener('pause', function(ev){
      if (ev.target && ev.target.tagName === 'VIDEO') reportBusy();
    }, true);
    document.addEventListener('ended', function(ev){
      if (ev.target && ev.target.tagName === 'VIDEO') reportBusy();
    }, true);
    setInterval(reportBusy, 4000);
  }
  reportBusy();
})();
''');
    } catch (_) {}
  }

  static Future<void> installCalmMode(WebViewController controller) async {
    try {
      await _ensurePlayerHelpers(controller);
      await controller.runJavaScript(r'''
(function(){
  var s = document.getElementById('aven-calm-style');
  if (!s) {
    s = document.createElement('style');
    s.id = 'aven-calm-style';
    (document.head || document.documentElement).appendChild(s);
  }
  s.textContent = [
    '*,*::before,*::after{animation:none!important;animation-play-state:paused!important;transition:none!important;scroll-behavior:auto!important}',
    'html{scroll-behavior:auto!important}',
    'video,audio{autoplay:false!important}',
  ].join('');

  function isGif(img) {
    var src = (img.currentSrc || img.src || img.getAttribute('src') || '').toLowerCase();
    if (!src) return false;
    if (src.indexOf('data:image/gif') === 0) return true;
    return /\.gif(\?|#|$)/i.test(src);
  }

  function freezeOne(img) {
    if (img.__avenFrozen) return;
    img.__avenFrozen = true;
    try {
      var w = img.naturalWidth || img.width;
      var h = img.naturalHeight || img.height;
      if (!w || !h || w > 1600 || h > 1600) {
        img.loading = 'lazy';
        img.decoding = 'async';
        return;
      }
      var c = document.createElement('canvas');
      c.width = w;
      c.height = h;
      var ctx = c.getContext('2d');
      if (!ctx) return;
      ctx.drawImage(img, 0, 0, w, h);
      img.src = c.toDataURL('image/png');
    } catch (e) {
      try {
        img.style.setProperty('image-rendering', 'auto');
        img.setAttribute('loading', 'lazy');
      } catch (e2) {}
    }
  }

  function freezeGifs(root) {
    var scope = root && root.querySelectorAll ? root : document;
    var imgs = scope.querySelectorAll ? scope.querySelectorAll('img') : [];
    var budget = 24;
    for (var i = 0; i < imgs.length && budget > 0; i++) {
      var img = imgs[i];
      if (img.__avenFrozen) continue;
      if (!isGif(img)) continue;
      budget--;
      if (!img.complete) {
        img.addEventListener('load', function(ev){ freezeOne(ev.target); }, {once:true});
        continue;
      }
      freezeOne(img);
    }
  }

  function quietMedia(){
    document.querySelectorAll('video,audio').forEach(function(m){
      try {
        if (window.__avenMediaSite || window.__avenWantPlay || !m.paused) return;
        if (!m.preload || m.preload === 'auto') m.preload = 'metadata';
      } catch(e) {}
    });
  }

  function wakePlayerIframes(){
    if (window.__avenWakePlayerIframes) window.__avenWakePlayerIframes();
  }

  function armSitePlayPoster(){
    if (window.__avenArmSitePlayPoster) window.__avenArmSitePlayPoster();
  }

  function wakePosterImages(){
    var nodes = document.querySelectorAll('img[data-src],img[data-lazy-src],img[data-original],img.lazyload');
    for (var i = 0; i < nodes.length; i++) {
      var img = nodes[i];
      try {
        var ds = img.getAttribute('data-src') || img.getAttribute('data-lazy-src') || img.getAttribute('data-original') || '';
        if (!ds) continue;
        var look = (ds + ' ' + (img.className || '')).toLowerCase();
        var parent = img.parentElement;
        var parentHint = parent ? ((parent.id || '') + ' ' + (parent.className || '')) : '';
        var isPoster = /poster|\/images\/tv\/|\/cover|\/thumb|tmdb|backdrop/.test(look)
          || /poster|series|film|movie|dizi|card/.test(parentHint.toLowerCase());
        var isAd = /banner-slot|ad-banner|728x90|cdn\.cdnhipter/.test(look + ' ' + parentHint.toLowerCase());
        if (!isPoster || isAd) continue;
        var cur = img.getAttribute('src') || '';
        if (!cur || cur.indexOf('data:') === 0) img.setAttribute('src', ds);
        img.removeAttribute('loading');
        img.loading = 'eager';
      } catch (e) {}
    }
  }

  function lazyImages(){
    document.querySelectorAll('img').forEach(function(img){
      try {
        var src = (img.currentSrc || img.src || img.getAttribute('data-src') || '').toLowerCase();
        if (/poster|\/images\/tv\//.test(src)) {
          img.removeAttribute('loading');
          img.loading = 'eager';
          return;
        }
        if (!img.getAttribute('loading')) img.loading = 'lazy';
        img.decoding = 'async';
      } catch(e) {}
    });
  }

  quietMedia();
  wakePlayerIframes();
  armSitePlayPoster();
  wakePosterImages();
  lazyImages();
  freezeGifs(document);
  if (!window.__avenCalmObs) {
    window.__avenCalmObs = true;
    var t = null;
    new MutationObserver(function(){
      if (t) return;
      var wait = window.__avenLite ? 1400 : 700;
      t = setTimeout(function(){
        t = null;
        quietMedia();
        wakePlayerIframes();
        armSitePlayPoster();
        wakePosterImages();
        lazyImages();
        freezeGifs(document);
      }, wait);
    }).observe(document.documentElement, {childList:true, subtree:true});
  }
})();
''');
    } catch (_) {}
  }

  static Future<void> installLiteCss(WebViewController controller, {required bool mediaSite}) async {
    try {
      await _ensurePlayerHelpers(controller);
      await controller.runJavaScript('''
(function(){
  window.__avenLite = true;
  window.__avenMediaSite = ${mediaSite ? 'true' : 'false'};
  var s = document.getElementById('aven-lite-style');
  if (!s) {
    s = document.createElement('style');
    s.id = 'aven-lite-style';
    (document.head || document.documentElement).appendChild(s);
  }
  s.textContent = window.__avenMediaSite
    ? [
        'img:not([src*="player"]):not([class*="player"]):not([src*="poster"]):not([src*="/images/tv/"]){content-visibility:auto;contain-intrinsic-size:240px 160px}',
        'img[src*="poster"],img[data-src*="poster"],img[src*="/images/tv/"],img[data-src*="/images/tv/"]{',
        'content-visibility:visible!important;contain:none!important;}',
        'video,audio,iframe,.video-js,.jwplayer,[data-player],#player,.player,.plyr{',
        'content-visibility:visible!important;contain:none!important;}',
        '.play-that-video:not([hidden]),.play-icon{',
        'content-visibility:visible!important;contain:none!important;}',
        '.video-container[hidden]{display:none!important}'
      ].join('')
    : [
        'img,picture,canvas{content-visibility:auto;contain-intrinsic-size:240px 160px}',
        'img[src*="poster"],img[data-src*="poster"],img[src*="/images/tv/"],img[data-src*="/images/tv/"]{',
        'content-visibility:visible!important;contain:none!important;}',
        'video,audio,iframe,.video-js,.jwplayer,[data-player],#player,.player,.plyr{',
        'content-visibility:visible!important;contain:none!important;}',
        '.play-that-video:not([hidden]),.play-icon{',
        'content-visibility:visible!important;contain:none!important;}',
        '.video-container[hidden]{display:none!important}',
        'img{image-rendering:auto}'
      ].join('');

  function quietMedia(){
    if (window.__avenMediaSite || window.__avenWantPlay) return;
    document.querySelectorAll('video,audio').forEach(function(m){
      try {
        if (!m.paused) return;
        if (!m.preload || m.preload === 'auto') m.preload = 'metadata';
      } catch(e) {}
    });
  }

  function deferImages(){
    var vh = window.innerHeight || 800;
    var imgs = document.querySelectorAll('img');
    var budget = 40;
    for (var i = 0; i < imgs.length && budget > 0; i++) {
      var img = imgs[i];
      try {
        if (!img.getAttribute('loading')) img.loading = 'lazy';
        img.decoding = 'async';
        var rect = img.getBoundingClientRect();
        var far = rect.top > vh * 2.2 || rect.bottom < -vh;
        if (far) {
          if (!img.getAttribute('fetchpriority')) img.setAttribute('fetchpriority', 'low');
        } else if (rect.top < vh * 1.2) {
          img.setAttribute('fetchpriority', 'auto');
        }
        budget--;
      } catch(e) {}
    }
  }

  function wakePlayerIframes(){
    if (window.__avenWakePlayerIframes) window.__avenWakePlayerIframes();
  }

  function armSitePlayPoster(){
    if (window.__avenArmSitePlayPoster) window.__avenArmSitePlayPoster();
  }

  quietMedia();
  wakePlayerIframes();
  armSitePlayPoster();
  deferImages();
  if (!window.__avenLiteObs) {
    window.__avenLiteObs = true;
    var t = null;
    var scrolling = false;
    window.addEventListener('scroll', function(){
      scrolling = true;
      if (t) return;
      t = setTimeout(function(){
        t = null;
        scrolling = false;
        quietMedia();
        wakePlayerIframes();
        armSitePlayPoster();
        deferImages();
      }, 1200);
    }, {passive:true, capture:true});
    new MutationObserver(function(){
      if (scrolling || t) return;
      t = setTimeout(function(){
        t = null;
        quietMedia();
        wakePlayerIframes();
        armSitePlayPoster();
        deferImages();
      }, 1400);
    }).observe(document.documentElement, {childList:true, subtree:true});
  }
})();
''');
    } catch (_) {}
  }

  static Future<void> installBannerCss(WebViewController controller) async {
    try {
      final css = avenBannerCosmeticCss;
      await controller.runJavaScript('''
(function(){
  var s = document.getElementById('aven-banner-style');
  if (!s) {
    s = document.createElement('style');
    s.id = 'aven-banner-style';
    (document.head || document.documentElement).appendChild(s);
  }
  s.textContent = ${jsonEncode(css)};
})();
''');
    } catch (_) {}
  }

  static Future<void> installAdblockCss(WebViewController controller) async {
    try {
      final css = avenFullAdblockCosmeticCss;
      await controller.runJavaScript('''
(function(){
  var s = document.getElementById('aven-adblock-style');
  if (!s) {
    s = document.createElement('style');
    s.id = 'aven-adblock-style';
    (document.head || document.documentElement).appendChild(s);
  }
  s.textContent = ${jsonEncode(css)};
})();
''');
    } catch (_) {}
  }

  static Future<void> installHooks(
    WebViewController controller, {
    required String pageHooks,
    required String videoWatch,
  }) async {
    try {
      await controller.runJavaScript(pageHooks);
      await controller.runJavaScript(videoWatch);
      await installCalmMode(controller);
    } catch (_) {}
  }
}
