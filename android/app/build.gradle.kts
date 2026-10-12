plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "ai.qompass.ghost"
    compileSdk = 36

    defaultConfig {
        // F-Droid applicationId; must match the fdroiddata recipe.
        applicationId = "ai.qompass.ghost"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"

        vectorDrawables {
            useSupportLibrary = true
        }

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            // Play Store uploads an AAB; F-Droid builds this type from source.
        }
        debug {
            applicationIdSuffix = ".debug"
        }
    }

    buildFeatures {
        compose = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }

    packaging {
        resources {
            // Bouncy Castle ships duplicate metadata; pick first.
            pickFirsts += setOf(
                "META-INF/DEPENDENCIES",
                "META-INF/LICENSE",
                "META-INF/LICENSE.md",
                "META-INF/LICENSE.txt",
                "META-INF/NOTICE",
                "META-INF/NOTICE.md",
                "META-INF/NOTICE.txt",
                "META-INF/versions/9/OSGI-INF/MANIFEST.MF"
            )
        }
    }
}

dependencies {
    // --- Tor (FOSS; no GMS) ---
    implementation("info.guardianproject:tor-android:0.4.9.6")

    // --- Email: IMAP/SMTP over Tor SOCKS (EPL/GPL+CE, FOSS) ---
    implementation("com.sun.mail:android-mail:1.6.7")
    implementation("com.sun.mail:android-activation:1.6.7")

    // --- OpenPGP (Bouncy Castle, MIT-style, FOSS) ---
    implementation("org.bouncycastle:bcprov-jdk18on:1.78.1")
    implementation("org.bouncycastle:bcpg-jdk18on:1.78.1")

    // --- Encrypted account storage (AndroidX, Apache 2.0) ---
    implementation("androidx.security:security-crypto:1.1.0-alpha06")

    // --- Compose UI ---
    val composeBom = platform("androidx.compose:compose-bom:2024.10.00")
    implementation(composeBom)
    androidTestImplementation(composeBom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.activity:activity-compose:1.9.2")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.6")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.6")

    // --- Coroutines: structured concurrency, no GlobalScope ---
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")

    // --- JVM unit tests: seeded-mail body extraction + decrypt flow ---
    testImplementation("junit:junit:4.13.2")

    // --- Instrumented tests: the reader screen on a real Android runtime ---
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    debugImplementation("androidx.compose.ui:ui-test-manifest")

    debugImplementation("androidx.compose.ui:ui-tooling")
}
