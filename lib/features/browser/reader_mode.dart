/// Compact article reader for TV WebView (enter / exit via JS).
const readerToggleScript = r'''
(function(){
  function restore(){
    try {
      var bak = window.__avenReaderBackup;
      if (!bak) return false;
      var style = document.getElementById('aven-reader-style');
      if (style) style.remove();
      document.documentElement.setAttribute('style', bak.htmlStyle || '');
      if (!bak.htmlStyle) document.documentElement.removeAttribute('style');
      document.body.setAttribute('style', bak.bodyStyle || '');
      if (!bak.bodyStyle) document.body.removeAttribute('style');
      document.body.innerHTML = bak.body;
      if (bak.title) document.title = bak.title;
      try {
        if (bak.scroll != null) window.scrollTo(0, bak.scroll);
      } catch (e) {}
      window.__avenReaderOn = false;
      window.__avenReaderBackup = null;
      return true;
    } catch (e) {
      return false;
    }
  }

  if (window.__avenReaderOn) {
    return restore() ? 'off' : 'fail';
  }

  function visible(el){
    if (!el || !el.getBoundingClientRect) return false;
    var r = el.getBoundingClientRect();
    return r.width > 40 && r.height > 40;
  }

  function cleanClone(root){
    var clone = root.cloneNode(true);
    var kill = clone.querySelectorAll(
      'script,style,noscript,iframe,nav,aside,footer,form,button,svg,canvas,video,audio,' +
      '[role="navigation"],[role="banner"],[role="complementary"],[role="contentinfo"],' +
      '.ad,.ads,.advert,.advertisement,.sidebar,.share,.social,.comments,.comment,' +
      '.newsletter,.popup,.modal,.cookie,.paywall,.related,.recommended,.promo'
    );
    for (var i = 0; i < kill.length; i++) {
      try { kill[i].remove(); } catch (e) {}
    }
    var junk = clone.querySelectorAll('[class*="ad-"],[id*="ad-"],[class*="share"],[class*="social"]');
    for (var j = 0; j < junk.length; j++) {
      try { junk[j].remove(); } catch (e) {}
    }
    return clone;
  }

  function score(el){
    if (!el || !visible(el)) return 0;
    var text = (el.innerText || '').replace(/\s+/g, ' ').trim();
    var len = text.length;
    if (len < 280) return 0;
    var p = el.querySelectorAll('p').length;
    var links = el.querySelectorAll('a').length;
    var imgs = el.querySelectorAll('img').length;
    var linkPenalty = Math.min(links * 18, len * 0.35);
    return len + p * 90 + imgs * 20 - linkPenalty;
  }

  function pickArticle(){
    var selectors = [
      'article',
      'main',
      '[role="main"]',
      '.post-content',
      '.entry-content',
      '.article-content',
      '.article-body',
      '.story-body',
      '#article-body',
      '#content',
      '.content',
      '.post',
      '.entry'
    ];
    var best = null;
    var bestScore = 0;
    for (var s = 0; s < selectors.length; s++) {
      var nodes = document.querySelectorAll(selectors[s]);
      for (var i = 0; i < nodes.length; i++) {
        var sc = score(nodes[i]);
        if (sc > bestScore) {
          bestScore = sc;
          best = nodes[i];
        }
      }
    }
    if (best && bestScore >= 400) return best;
    var blocks = document.body ? document.body.children : [];
    for (var b = 0; b < blocks.length; b++) {
      var sc2 = score(blocks[b]);
      if (sc2 > bestScore) {
        bestScore = sc2;
        best = blocks[b];
      }
    }
    return bestScore >= 400 ? best : null;
  }

  var source = pickArticle();
  if (!source) return 'none';

  var title = '';
  try {
    var h = source.querySelector('h1') || document.querySelector('h1');
    title = (h && h.innerText) ? h.innerText.trim() : (document.title || '');
  } catch (e) {
    title = document.title || '';
  }

  var article = cleanClone(source);
  try {
    var nestedH1 = article.querySelector('h1');
    if (nestedH1 && title && nestedH1.innerText.trim() === title) nestedH1.remove();
  } catch (e) {}

  window.__avenReaderBackup = {
    body: document.body.innerHTML,
    title: document.title,
    scroll: window.scrollY || 0,
    htmlStyle: document.documentElement.getAttribute('style') || '',
    bodyStyle: document.body.getAttribute('style') || ''
  };

  document.body.innerHTML = '';

  var lock = document.getElementById('aven-reader-style');
  if (!lock) {
    lock = document.createElement('style');
    lock.id = 'aven-reader-style';
    (document.head || document.documentElement).appendChild(lock);
  }
  // Many sites pin html/body to overflow:hidden + height:100% (inner scroller).
  // Reader content must scroll on the document itself for the TV cursor.
  lock.textContent = [
    'html,body{overflow-x:hidden!important;overflow-y:auto!important;',
    'height:auto!important;min-height:100%!important;max-height:none!important;',
    'position:static!important;overscroll-behavior:auto!important;}',
    'body{background:#0B0D0F!important;color:#F3F5F7!important;margin:0!important;',
    'font-family:sans-serif!important;}',
    '#aven-reader-root,#aven-reader-body{overflow:visible!important;height:auto!important;',
    'max-height:none!important;color:#F3F5F7!important;}',
    // Site styles (Wikipedia etc.) keep muted gray text — force TV-readable contrast.
    '#aven-reader-root,#aven-reader-root *{',
    'color:#F3F5F7!important;opacity:1!important;',
    '-webkit-text-fill-color:#F3F5F7!important;',
    'text-shadow:none!important;background-color:transparent!important;',
    'background-image:none!important;filter:none!important;',
    'mix-blend-mode:normal!important;}',
    '#aven-reader-root a,#aven-reader-root a *{color:#8AB4F8!important;',
    '-webkit-text-fill-color:#8AB4F8!important;text-decoration:underline!important;}',
    '#aven-reader-root h1,#aven-reader-root h2,#aven-reader-root h3,',
    '#aven-reader-root h4,#aven-reader-root h5,#aven-reader-root h6{',
    'color:#FFFFFF!important;-webkit-text-fill-color:#FFFFFF!important;font-weight:700!important;}',
    '#aven-reader-root img,#aven-reader-root svg,#aven-reader-root video{',
    'color:unset!important;-webkit-text-fill-color:unset!important;',
    'opacity:1!important;background:transparent!important;filter:none!important;}',
    '#aven-reader-root table,#aven-reader-root th,#aven-reader-root td{',
    'border-color:rgba(243,245,247,.25)!important;}'
  ].join('');

  document.documentElement.style.cssText =
    'overflow-y:auto!important;height:auto!important;min-height:100%!important;background:#0B0D0F!important;';
  document.body.style.cssText =
    'overflow-y:auto!important;height:auto!important;min-height:100%!important;' +
    'background:#0B0D0F!important;color:#F3F5F7!important;margin:0!important;' +
    'font-family:sans-serif!important;position:static!important;';

  var wrap = document.createElement('div');
  wrap.id = 'aven-reader-root';
  wrap.style.cssText = 'max-width:44rem;margin:0 auto;padding:2rem 2.4rem 4rem;overflow:visible;color:#F3F5F7;';

  var hint = document.createElement('p');
  hint.textContent = 'Okuyucu · menüden geri dön';
  hint.style.cssText = 'margin:0 0 1.2rem;font-size:0.95rem;color:#C5CAD0!important;opacity:1!important;';
  wrap.appendChild(hint);

  if (title) {
    var heading = document.createElement('h1');
    heading.textContent = title;
    heading.style.cssText = 'font-size:2rem;line-height:1.25;margin:0 0 1.2rem;font-weight:700;color:#FFFFFF!important;';
    wrap.appendChild(heading);
  }

  var host = document.createElement('div');
  host.id = 'aven-reader-body';
  host.style.cssText = 'font-size:1.35rem;line-height:1.7;overflow:visible;color:#F3F5F7!important;';
  host.appendChild(article);
  wrap.appendChild(host);
  document.body.appendChild(wrap);

  try {
    host.querySelectorAll('*').forEach(function(el){
      try {
        el.style.removeProperty('color');
        el.style.removeProperty('opacity');
        el.style.removeProperty('-webkit-text-fill-color');
        el.style.removeProperty('filter');
      } catch (e) {}
    });
    host.querySelectorAll('img').forEach(function(img){
      img.style.maxWidth = '100%';
      img.style.height = 'auto';
      img.loading = 'lazy';
    });
  } catch (e) {}

  try {
    document.documentElement.scrollTop = 0;
    document.body.scrollTop = 0;
    window.scrollTo(0, 0);
  } catch (e) {}
  window.__avenReaderOn = true;
  return 'on';
})();
''';
