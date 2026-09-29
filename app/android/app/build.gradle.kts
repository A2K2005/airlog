plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "app.airlog.airlog"
    // 37 (not 36): permission_handler_android 14.1 AAR metadata requires it.
    // targetSdk stays 36 (runtime behaviour), minSdk 26 (health plugin).
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "app.airlog.airlog"
        minSdk = 26
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // flutter_appauth redirect scheme (Google Health API "Enhanced mode").
        // The default is a harmless placeholder so the app builds without a
        // Google Cloud client. For a real client pass the reversed client id:
        //   flutter build apk -PairlogOAuthScheme=com.googleusercontent.apps.<id>
        //     --dart-define=GOOGLE_OAUTH_CLIENT_ID=<id>.apps.googleusercontent.com
        // (or put airlogOAuthScheme=... in android/gradle.properties).
        manifestPlaceholders["appAuthRedirectScheme"] =
            (project.findProperty("airlogOAuthScheme") as String?) ?: "app.airlog.oauth"
    }

    buildTypes {
        release {
            // Unsigned for now: debug keys so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Same Health Connect client the `health` 13.3.2 plugin uses (its
    // android/build.gradle), so there is one version on the classpath.
    implementation("androidx.health.connect:connect-client:1.2.0-alpha02")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
}

flutter {
    source = "../.."
}
