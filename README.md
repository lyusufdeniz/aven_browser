# Aven Browser

Android web browser for phones and Mi Box class boxes. Flutter draws the shell. TV pages use the system WebView. Phone pages use GeckoView.

The remote moves a cursor. OK clicks. Up, while the cursor is already on the top edge, focuses the address bar.

Two APKs share `dev.furina.avenbrowser`. TV uses the system WebView. Phone uses GeckoView. Play serves the higher version code when a device matches both, so the TV build is always one code above the phone build from the same pubspec number.

```
flutter run --flavor tv
flutter run --flavor mobile
flutter build apk --flavor tv --release
flutter build apk --flavor mobile --release
```

The APKs are `build/app/outputs/flutter-apk/app-tv-release.apk` and `app-mobile-release.apk`. Sideload the TV build onto the box. Flutter 3.47 needs Android 7 or newer, so a Mi Box still on Android 6 cannot run it. Mi Box units updated to Android 8 can. The phone build needs Android 8 or newer.
