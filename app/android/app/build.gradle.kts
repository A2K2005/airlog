import java.util.Base64
import java.net.URI

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// One OAuth build input shared with Dart prevents redirect-scheme drift.
val dartDefines = (project.findProperty("dart-defines") as String?)
    ?.split(",")?.mapNotNull { encoded ->
        runCatching { String(Base64.getDecoder().decode(encoded)) }.getOrNull()
    }?.associate { entry ->
        entry.substringBefore("=") to entry.substringAfter("=", "")
    } ?: emptyMap()
val oauthClient = dartDefines["GOOGLE_OAUTH_CLIENT_ID"].orEmpty().trim()
val oauthOverride = dartDefines["GOOGLE_OAUTH_REDIRECT"].orEmpty().trim()
val oauthScheme = if (oauthOverride.isNotEmpty()) {
    requireNotNull(URI(oauthOverride).scheme) { "OAuth redirect needs a URI scheme" }
} else if (oauthClient.endsWith(".apps.googleusercontent.com")) {
    "com.googleusercontent.apps.${oauthClient.removeSuffix(".apps.googleusercontent.com")}"
} else { "app.airlog.oauth" }
val releaseCredentials = listOf(
    "AIRLOG_KEYSTORE", "AIRLOG_KEYSTORE_PASSWORD", "AIRLOG_KEY_ALIAS", "AIRLOG_KEY_PASSWORD"
).associateWith { System.getenv(it).orEmpty() }
val releaseConfigured = releaseCredentials.values.all { it.isNotBlank() }
gradle.taskGraph.whenReady {
    if (allTasks.any { it.path.startsWith(":app:") && it.name.endsWith("Release") }) {
        require(releaseConfigured) {
            "Release signing is not configured. Set AIRLOG_KEYSTORE, AIRLOG_KEYSTORE_PASSWORD, " +
                "AIRLOG_KEY_ALIAS and AIRLOG_KEY_PASSWORD securely. Use --debug for local QA."
        }
    }
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
        manifestPlaceholders["appAuthRedirectScheme"] = oauthScheme
    }

    signingConfigs {
        create("release") {
            if (releaseConfigured) {
                storeFile = file(releaseCredentials.getValue("AIRLOG_KEYSTORE"))
                storePassword = releaseCredentials.getValue("AIRLOG_KEYSTORE_PASSWORD")
                keyAlias = releaseCredentials.getValue("AIRLOG_KEY_ALIAS")
                keyPassword = releaseCredentials.getValue("AIRLOG_KEY_PASSWORD")
            }
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
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
