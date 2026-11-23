import java.util.Properties

plugins {
    id("com.android.application")
    // Flutter Gradle 插件需在 Android 应用插件之后应用。
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseSigningProperties = Properties().apply {
    val propertiesFile = rootProject.file("key.properties")
    if (propertiesFile.exists()) propertiesFile.inputStream().use { load(it) }
}

android {
    namespace = "cn.yunmoan.thmr.thmr_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Android 包名也用于升级兼容性检查，已安装版本的更新包需沿用此值。
        applicationId = "cn.yunmoan.thmr.thmr_app"
        // Android 最低和目标 SDK 版本由 Flutter Gradle 插件提供。
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // 版本默认取自 pubspec.yaml，也可由 Flutter 构建参数覆盖。拆分 APK 时，
        // Flutter 默认在 versionCode 上加 1000 × ABI_VERSION。
        // Gradle 参数 -P force-version-code-ignoring-abi=true 可关闭此偏移。
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        val releaseKeystore = System.getenv("THMR_ANDROID_KEYSTORE_PATH")
            ?: releaseSigningProperties.getProperty("storeFile")
        if (!releaseKeystore.isNullOrBlank()) {
            create("release") {
                storeFile = file(releaseKeystore)
                storePassword = System.getenv("THMR_ANDROID_KEYSTORE_PASSWORD")
                    ?: releaseSigningProperties.getProperty("storePassword")
                keyAlias = System.getenv("THMR_ANDROID_KEY_ALIAS")
                    ?: releaseSigningProperties.getProperty("keyAlias")
                keyPassword = System.getenv("THMR_ANDROID_KEY_PASSWORD")
                    ?: releaseSigningProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // 配置了发布密钥时使用正式签名，否则使用调试密钥供本地运行或预览。
            // 正式发布的 CI 要求提供发布密钥。
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
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
