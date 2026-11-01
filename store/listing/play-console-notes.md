# Play Console doldurma notları

## Veri güvenliği (Data safety) formu

Koddan çıkan duruma göre önerilen cevaplar:

- **Uygulama kullanıcı verisi topluyor veya paylaşıyor mu?** Hayır.
  Geçmiş, yer imleri ve ayarlar cihazda kalıyor; geliştiriciye hiçbir şey gitmiyor.
  Arama önerileri ve favicon istekleri, kullanıcının başlattığı tarayıcı işlevi
  olarak sayılır (Google'ın tanımına göre "kullanıcının doğrudan başlattığı,
  bir hizmete yapılan istek" toplama sayılmaz).
- **Veriler aktarım sırasında şifreleniyor mu?** Evet (arama, öneri, favicon ve
  EasyList istekleri HTTPS). Not: ziyaret edilen HTTP siteler şifresiz açılır,
  bu sitenin kendi tercihi.
- **Kullanıcı veri silme isteyebilir mi?** Veri sunucuda tutulmadığı için
  "Uygulama veri toplamıyor" seçeneği yeterli.

## Hassas izin beyanları

- **REQUEST_INSTALL_PACKAGES:** Play bu izni kısıtlar. Beyan formunda ana işlev
  olarak "Web tarayıcı / indirilen dosyaları açma" seçin. Reddedilirse izni
  kaldırıp APK'ları sistem dosya uygulamasına bırakmak gerekir.
- **Konum (ACCESS_FINE/COARSE_LOCATION):** Arka planda kullanılmıyor; sadece
  sitelerin konum isteği için. Arka plan konum beyanı gerekmez.
- **NEARBY_WIFI_DEVICES:** `neverForLocation` işaretli, ek beyan gerekmez.

## İçerik derecelendirmesi

Tarayıcılar için anketin "Uygulama kullanıcıların internete sınırsız erişmesine
izin veriyor mu?" sorusuna **Evet** deyin; bu genelde 12+/PEGI 12 civarı bir
derece verir.

## Hedef kitle

18 yaş ve üstü (veya 13+). "Çocuklara yönelik" işaretlemeyin.

## Android TV için

- TV ekran görüntüsü (en az 1 adet, 16:9) ve **TV banner'ı (1280×720)** zorunlu.
- Uygulamanın manifestinde `android:banner` var, `LEANBACK_LAUNCHER` kategorisinin
  de bulunduğundan emin olun; yoksa Play TV'de listelemez.
- Play TV incelemesi kumandayla tam kullanılabilirlik ister; imleç ve D-pad odağı
  bunu karşılıyor.

## Görsellerdeki marka kullanımı

Mağaza görsellerinde Netflix, YouTube, Disney+ gibi üçüncü taraf logoları
kullanılmadı. Play, başka markaların logolarını mağaza görsellerinde
kullanmayı "yanıltıcı/izinsiz marka kullanımı" sayıp listelemeyi reddedebilir.
Ekranlardaki siteler hayalî örnek sitelerdir.

## Dosya listesi

Diller (Play Console dil kodu = klasör adı): en-US, tr-TR, es-ES, pt-BR, de-DE,
fr-FR, it-IT, ru-RU, id, hi-IN, ar, ja-JP. Her dilin mağaza metni
`store/listing/<kod>.md` içinde.

| Dosya | Boyut | Play Console alanı |
|---|---|---|
| `store/graphics/icon-512.png` | 512×512 | Uygulama simgesi (tüm diller) |
| `store/graphics/tv-banner.png` | 1280×720 | TV banner'ı (tüm diller) |
| `store/graphics/feature-graphic/<kod>.png` | 1024×500 | Öne çıkan grafik |
| `store/graphics/phone/<kod>/1-8.png` | 1080×1920 | Telefon ekran görüntüleri |
| `store/graphics/tv/<kod>/1-5.png` | 1920×1080 | Android TV ekran görüntüleri |

İspanyolca için es-ES dosyalarını es-419 ve es-US listelerine de yükleyebilirsiniz.

## Görselleri yeniden üretmek

Metinler `store/design/studio.html` (en/tr) ve `store/design/i18n/<kod>.json`
(diğer diller, anahtarlar İngilizce metin) içinde. Değiştirdikten sonra:

    store/design/render.sh                      # hepsi
    LANGS="de-DE" store/design/render.sh p1 t1  # tek dil, tek görsel
