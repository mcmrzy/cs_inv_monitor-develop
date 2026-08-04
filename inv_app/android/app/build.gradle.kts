import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use(keystoreProperties::load)
}

val releaseStoreFile = System.getenv("ANDROID_KEYSTORE_PATH") ?: keystoreProperties.getProperty("storeFile")
val releaseStorePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD") ?: keystoreProperties.getProperty("storePassword")
val releaseKeyAlias = System.getenv("ANDROID_KEY_ALIAS") ?: keystoreProperties.getProperty("keyAlias")
val releaseKeyPassword = System.getenv("ANDROID_KEY_PASSWORD") ?: keystoreProperties.getProperty("keyPassword")
val hasReleaseSigning = listOf(
    releaseStoreFile,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
).all { !it.isNullOrBlank() }

android {
    namespace = "com.csergy.app1"
    compileSdk = 37  // permission_handler 13+ 要求 compileSdk 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.csergy.app1"
        minSdk = 29  // jiguang_auth 要求 Android 10+
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // JPush / JVerify 配置
        manifestPlaceholders["JPUSH_PKGNAME"] = "com.csergy.app1"
        manifestPlaceholders["JPUSH_APPKEY"] =
            System.getenv("JPUSH_APP_KEY") ?: "5a5df0da74b0ec20becb9bb1"
        manifestPlaceholders["JPUSH_CHANNEL"] = "inv_app"

        // JVerify 原生 SDK 需要 NDK abiFilters
        ndk {
            abiFilters += listOf("armeabi-v7a", "arm64-v8a", "x86_64")
        }
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseStoreFile!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfigs.findByName("release")?.let { signingConfig = it }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}

flutter {
    source = "../.."
}
