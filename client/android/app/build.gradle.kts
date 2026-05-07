plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.voiceguard.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.voiceguard.app"
        minSdk = flutter.minSdkVersion
        targetSdk = 33
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk {
            // 실기기 배포용: arm64-v8a만 (APK 크기 최소화)
            // 에뮬레이터(x86_64) 테스트 시 아래 줄 교체:
            // abiFilters += setOf("arm64-v8a", "x86_64")
            abiFilters += setOf("arm64-v8a")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("org.tensorflow:tensorflow-lite-select-tf-ops:2.14.0")
}
