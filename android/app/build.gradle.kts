import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Chave de release: vem do ambiente (CI) ou de android/key.properties
// (máquina própria, fora do git). Sem ela, o build local usa a de debug.
val releaseKeystore = System.getenv("ANDROID_KEYSTORE_PATH")
val releasePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
val releaseAlias = System.getenv("ANDROID_KEY_ALIAS")
val keyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

android {
    namespace = "com.brainw4llet.brainw4llet"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.brainw4llet.brainw4llet"
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

    signingConfigs {
        create("release") {
            val store = releaseKeystore ?: keyProperties.getProperty("storeFile")
            if (store != null) {
                storeFile = file(store)
                storeType = "pkcs12"
                storePassword = releasePassword ?: keyProperties.getProperty("storePassword")
                keyPassword = storePassword
                keyAlias = releaseAlias ?: keyProperties.getProperty("keyAlias")
            }
        }
    }

    buildTypes {
        release {
            val release = signingConfigs.getByName("release")
            signingConfig =
                if (release.storeFile != null) release else signingConfigs.getByName("debug")
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
