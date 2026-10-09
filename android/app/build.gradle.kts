plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.furina.avenbrowser"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    buildFeatures {
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.furina.avenbrowser"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // One applicationId, two APKs. Play installs the highest versionCode that
    // matches the device. TV matches both, so its code stays one above mobile
    // for the same pubspec build number. The next build number lifts both.
    flavorDimensions += "form"
    productFlavors {
        create("mobile") {
            dimension = "form"
            minSdk = maxOf(flutter.minSdkVersion, 26)
            versionCode = flutter.versionCode * 10
            versionName = flutter.versionName
        }
        create("tv") {
            dimension = "form"
            versionCode = flutter.versionCode * 10 + 1
            versionName = flutter.versionName
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.webkit:webkit:1.12.1")
    // Phone APK only. TV stays on the system WebView.
    // 152 stays on compileSdk 36. Newer betas pull AndroidX that wants API 37.
    add("mobileImplementation", "org.mozilla.geckoview:geckoview-beta:152.0.20260610111934")
}
