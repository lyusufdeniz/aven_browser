package com.avenbrowser.aven_browser


// CSS only — no MutationObserver (that froze scroll).
internal val cosmeticHideRule =
    "{display:none!important;visibility:hidden!important;height:0!important;max-height:0!important;" +
        "min-height:0!important;width:0!important;max-width:0!important;overflow:hidden!important;" +
        "opacity:0!important;pointer-events:none!important;position:absolute!important;left:-10000px!important}"

internal val bannerCosmeticCss = (
    "iframe[src*='doubleclick'],iframe[src*='googlesyndication'],iframe[src*='exoclick']," +
        "iframe[src*='exosrv'],iframe[src*='propeller'],iframe[src*='popads'],iframe[src*='popcash']," +
        "iframe[src*='juicyads'],iframe[src*='adsterra'],iframe[src*='hilltopads'],iframe[src*='clickadu']," +
        "iframe[src*='trafficjunky'],iframe[src*='/pagead'],iframe[src*='advert'],iframe[id*='google_ads']," +
        "iframe[width='728'][height='90'],iframe[width='300'][height='250'],iframe[width='160'][height='600']," +
        "iframe[width='336'][height='280'],iframe[width='320'][height='50'],ins.adsbygoogle," +
        "[data-ad-client],[data-ad-slot],[id^='google_ads_'],[id^='div-gpt-ad'],[id^='ads-']," +
        // Avoid [class^='ads-']: some players wrap media in classes starting with ads-.
        "[class*='adsbygoogle'],[class*='ad-banner'],[class*='banner-ad']," +
        "[class*='ads-banner'],[class*='ad-slot']," +
        "[class*='sticky-ad'],[class*='floating-ad'],[class*='popup-ad']," +
        ".banner-slot,.adsbox,.textads,.banner_ads,.banner-ads,.adbox,.ADBox,.AdBox,.adbox-wrapper," +
        ".adSocial,.ad-unit,.afs_ads,.ad-zone,.ad-space"
    ) + cosmeticHideRule

internal val fullAdblockCosmeticCss = (
    bannerCosmeticCss.removeSuffix(cosmeticHideRule) +
        ",[class*='sponsored'],[class*='taboola'],[class*='outbrain'],[class*='mgid']," +
        "[class*='revcontent'],[id*='onesignal'],[class*='onesignal'],[class*='push-notification']"
    ) + cosmeticHideRule

internal val cosmeticScript = """
(function(){
  var s = document.getElementById('aven-adblock-style');
  if (!s) {
    s = document.createElement('style');
    s.id = 'aven-adblock-style';
    (document.head || document.documentElement).appendChild(s);
  }
  s.textContent = ${jsonQuote(fullAdblockCosmeticCss)};
})();
""".trimIndent()

internal val bannerCosmeticScript = """
(function(){
  var s = document.getElementById('aven-banner-style');
  if (!s) {
    s = document.createElement('style');
    s.id = 'aven-banner-style';
    (document.head || document.documentElement).appendChild(s);
  }
  s.textContent = ${jsonQuote(bannerCosmeticCss)};
})();
""".trimIndent()

internal fun jsonQuote(value: String): String {
    return "\"" + value
        .replace("\\", "\\\\")
        .replace("\"", "\\\"")
        .replace("\n", "\\n")
        .replace("\r", "") + "\""
}
