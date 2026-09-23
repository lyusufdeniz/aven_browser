# Aven Browser

Android TV web browser for Mi Box class boxes. Flutter draws the shell. The system WebView, which is Chromium, draws the page.

The remote moves a cursor. OK clicks. Up, while the cursor is already on the top edge, focuses the address bar.

```
flutter build apk --release
```

The APK is `build/app/outputs/flutter-apk/app-release.apk`. Sideload it onto the box. Flutter 3.47 needs Android 7 or newer, so a Mi Box still on Android 6 cannot run it. Mi Box units updated to Android 8 can.
