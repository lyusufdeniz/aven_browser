/// Generic banner / ad cosmetics for all sites (TV WebView).
/// Keep selectors conservative: hide ads, not article chrome.
const avenBannerHide =
    '{display:none!important;visibility:hidden!important;height:0!important;'
    'max-height:0!important;min-height:0!important;width:0!important;'
    'max-width:0!important;overflow:hidden!important;opacity:0!important;'
    'pointer-events:none!important;position:absolute!important;left:-10000px!important}';

const avenBannerSelectors = [
  "iframe[src*='doubleclick']",
  "iframe[src*='googlesyndication']",
  "iframe[src*='googletagservices']",
  "iframe[src*='exoclick']",
  "iframe[src*='exosrv']",
  "iframe[src*='propeller']",
  "iframe[src*='popads']",
  "iframe[src*='popcash']",
  "iframe[src*='juicyads']",
  "iframe[src*='adsterra']",
  "iframe[src*='hilltopads']",
  "iframe[src*='clickadu']",
  "iframe[src*='trafficjunky']",
  "iframe[src*='highperformanceformat']",
  "iframe[src*='/pagead']",
  "iframe[src*='advert']",
  "iframe[id*='google_ads']",
  "iframe[name*='google_ads']",
  "iframe[width='728'][height='90']",
  "iframe[width='970'][height='90']",
  "iframe[width='970'][height='250']",
  "iframe[width='300'][height='250']",
  "iframe[width='300'][height='600']",
  "iframe[width='160'][height='600']",
  "iframe[width='336'][height='280']",
  "iframe[width='320'][height='50']",
  "iframe[width='320'][height='100']",
  'ins.adsbygoogle',
  '[data-ad-client]',
  '[data-ad-slot]',
  '[data-ad-unit]',
  "[id^='google_ads_']",
  "[id^='div-gpt-ad']",
  "[id^='ads-']",
  "[class^='ads-']",
  "[class*='adsbygoogle']",
  "[class*='ad-banner']",
  "[class*='ad_banner']",
  "[class*='banner-ad']",
  "[class*='banner_ad']",
  "[class*='ads-banner']",
  "[class*='ad-slot']",
  "[class*='adslot']",
  "[class*='sticky-ad']",
  "[class*='floating-ad']",
  "[class*='float-ad']",
  "[class*='popup-ad']",
  "[class*='pop-ad']",
  "[id*='reklam']",
  "[class*='reklam']",
  // Streaming-site display banners — keep light; heavy host scrapes broke players.
  '.banner-slot',
  '#footerFixedDiv',
  '#psContainer',
  'iframe#psContainer',
  '#cts_test',
  '#ad_ctd',
  '.adsbox',
  '.textads',
  '.banner_ads',
  '.banner-ads',
  '.adbox',
  '.ADBox',
  '.AdBox',
  '.adbox-wrapper',
  '.adSocial',
  '.ad-unit',
  '.afs_ads',
  '.ad-zone',
  '.ad-space',
];

const avenAdblockExtraSelectors = [
  "[class*='sponsored']",
  "[class*='sponsor-']",
  "[id*='taboola']",
  "[class*='taboola']",
  "[id*='outbrain']",
  "[class*='outbrain']",
  "[class*='mgid']",
  "[class*='revcontent']",
  "[id*='onesignal']",
  "[class*='onesignal']",
  "[class*='push-notification']",
  // Do NOT hide .video-ads / .preroll / [class*='vast-'] — players stall.
];

String avenCosmeticCss(List<String> selectors) => '${selectors.join(',')}$avenBannerHide';

String get avenBannerCosmeticCss => avenCosmeticCss(avenBannerSelectors);

String get avenFullAdblockCosmeticCss =>
    avenCosmeticCss([...avenBannerSelectors, ...avenAdblockExtraSelectors]);
