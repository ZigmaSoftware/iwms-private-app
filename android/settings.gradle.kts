pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
        flutterSdkPath
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"

    // UPDATED AGP VERSIONS
    id("com.android.application") version "8.9.1" apply false
    id("com.android.library") version "8.9.1" apply false

    // Kotlin is fine
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false

    // Firebase Cloud Messaging (push notifications). Only actually applied in
    // app/build.gradle.kts when android/app/google-services.json exists, so the
    // build stays green until Firebase is configured — see that file.
    id("com.google.gms.google-services") version "4.4.2" apply false
}

include(":app")
