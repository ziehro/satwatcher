plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    ndkVersion = "27.0.12077973"
    namespace = "com.ziehro.satwatcher"
    compileSdk = flutter.compileSdkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "11"
    }

    defaultConfig {
        applicationId = "com.ziehro.satwatcher"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

dependencies {
    // Core library desugaring is required because isCoreLibraryDesugaringEnabled is set to true above
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.3")

    // MOVED: This line must be inside the dependencies block
    implementation("androidx.work:work-runtime:2.9.0")
}

flutter {
    source = "../.."
}