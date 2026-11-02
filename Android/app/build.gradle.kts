import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

val localProperties = Properties().apply {
    val file = rootProject.file("local.properties")
    if (file.isFile) file.inputStream().use { load(it) }
}
// Google Maps key: GitHub secret ANDROID_MAPS_API_KEY or local.properties MAPS_API_KEY.
// Without a key the app uses its built-in OpenStreetMap map instead.
val mapsApiKey: String = (System.getenv("ANDROID_MAPS_API_KEY") ?: localProperties.getProperty("MAPS_API_KEY") ?: "").trim()
val defaultServer: String = (System.getenv("RJ_DEFAULT_SERVER") ?: "https://find.rjuhas.eu").trim()
val appVersionCode = (System.getenv("RJ_ANDROID_VERSION_CODE") ?: "10").toInt()

android {
    namespace = "eu.rjuhas.rjtracker.android"
    compileSdk = 37

    defaultConfig {
        applicationId = "eu.rjuhas.rjtracker.android"
        minSdk = 26
        targetSdk = 36
        versionCode = appVersionCode
        versionName = "1.0.0"
        manifestPlaceholders["MAPS_API_KEY"] = mapsApiKey
        buildConfigField("String", "MAPS_API_KEY", "\"$mapsApiKey\"")
        buildConfigField("String", "DEFAULT_SERVER", "\"$defaultServer\"")
    }

    // The release key is never stored in this public repository. CI decodes the
    // ANDROID_KEYSTORE_BASE64 secret; locally ANDROID_KEYSTORE_FILE can point to
    // the keystore. Without one, the build falls back to the debug key (an APK
    // signed differently cannot install over an existing one).
    val keystorePath = System.getenv("ANDROID_KEYSTORE_FILE").orEmpty()
    val hasReleaseKey = keystorePath.isNotBlank() && file(keystorePath).isFile
    signingConfigs {
        if (hasReleaseKey) create("family") {
            storeFile = file(keystorePath)
            storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
            keyAlias = System.getenv("ANDROID_KEY_ALIAS") ?: "rjtracker"
            keyPassword = System.getenv("ANDROID_KEY_PASSWORD") ?: System.getenv("ANDROID_KEYSTORE_PASSWORD")
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.getByName(if (hasReleaseKey) "family" else "debug")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
    packaging {
        resources.excludes += "/META-INF/{AL2.0,LGPL2.1}"
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.ui.graphics)
    implementation(libs.compose.ui.tooling.preview)
    implementation(libs.compose.material3)
    implementation(libs.compose.animation)
    implementation(libs.compose.icons.extended)
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.core.splashscreen)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.process)
    implementation(libs.androidx.navigation.compose)
    implementation(libs.androidx.datastore)
    implementation(libs.androidx.work)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.okhttp)
    implementation(libs.maps.compose)
    implementation(libs.play.services.maps)
    implementation(libs.osmdroid)
    debugImplementation(libs.compose.ui.tooling)
    testImplementation(libs.junit)
}
