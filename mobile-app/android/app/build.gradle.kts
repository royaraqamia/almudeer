import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// Load key.properties for release signing
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "com.royaraqamia.almudeer"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    signingConfigs {
        create("release") {
            // Priority: Environment Variable > key.properties
            keyAlias = System.getenv("ANDROID_KEY_ALIAS") ?: (keystoreProperties["keyAlias"] as String?) ?: "almudeer-release"
            keyPassword = System.getenv("ANDROID_KEY_PASSWORD") ?: (keystoreProperties["keyPassword"] as String?) ?: ""
            storePassword = System.getenv("ANDROID_STORE_PASSWORD") ?: (keystoreProperties["storePassword"] as String?) ?: ""

            val storeFilePath = System.getenv("ANDROID_STORE_FILE") ?: (keystoreProperties["storeFile"] as String?) ?: "almudeer-release-2026.jks"
            storeFile = file(storeFilePath)
        }
    }

    dependencies {
        coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
        // Import the Firebase BoM
        implementation(platform("com.google.firebase:firebase-bom:33.7.0"))

        // Add the dependencies for the Firebase products you want to use
        // When using the BoM, don't specify versions in Firebase dependencies
        implementation("com.google.firebase:firebase-analytics")
        implementation("com.google.firebase:firebase-messaging")
        implementation("com.google.firebase:firebase-installations")
        implementation("com.google.firebase:firebase-common-ktx")

        // Play Services - pinned versions for stability (not managed by Firebase BoM)
        // These versions are tested compatible with firebase-bom:33.7.0
        implementation("com.google.android.gms:play-services-base:18.5.0")
        implementation("com.google.android.gms:play-services-measurement-api:22.1.2")

        // WorkManager - required by workmanager plugin
        implementation("androidx.work:work-runtime:2.10.0")
    }

    configurations.all {
        resolutionStrategy {
            // Force stable versions to avoid AGP 8.9.1 requirement
            force("androidx.browser:browser:1.7.0")
            force("androidx.activity:activity-ktx:1.8.2")
            force("androidx.activity:activity:1.8.2")
            force("androidx.core:core-ktx:1.12.0")
            force("androidx.core:core:1.12.0")
            // Strictly/Force Kotlin stdlib to match plugin version to avoid metadata incompatibility
            force("org.jetbrains.kotlin:kotlin-stdlib:2.1.0")
            // Force WorkManager version for workmanager plugin
            force("androidx.work:work-runtime:2.10.0")
            force("androidx.work:work-runtime-ktx:2.10.0")
        }
        exclude(group = "androidx.localbroadcastmanager", module = "localbroadcastmanager")
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.royaraqamia.almudeer"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    buildTypes {
        release {
            // Enable minification and shrinking
            isMinifyEnabled = true
            isShrinkResources = true

            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )

            // Apply signing configuration
            signingConfig = signingConfigs.getByName("release")
        }
    }

    // Reduce APK size
    packaging {
        resources {
            excludes += listOf(
                "META-INF/DEPENDENCIES",
                "META-INF/LICENSE",
                "META-INF/LICENSE.txt",
                "META-INF/NOTICE",
                "META-INF/NOTICE.txt"
            )
        }
        jniLibs {
            excludes += listOf(
                // Exclude unused Agora extensions (Video related) since we only use Audio
                "**/libagora_spatial_audio_extension.so",
                "**/libagora_clear_vision_extension.so",
                "**/libagora_content_inspect_extension.so",
                "**/libagora_video_avc_decoder_extension.so",
                "**/libagora_video_avc_encoder_extension.so",
                "**/libagora_video_hevc_decoder_extension.so",
                "**/libagora_video_hevc_encoder_extension.so",
                "**/libagora_video_av1_decoder_extension.so",
                "**/libagora_video_av1_encoder_extension.so",
                "**/libagora_video_decoder_extension.so",
                "**/libagora_video_encoder_extension.so",
                "**/libagora_video_process_extension.so",
                "**/libagora_video_quality_analyzer_extension.so",
                "**/libagora_ai_echo_cancellation_extension.so",
                "**/libagora_ai_noise_suppression_extension.so",
                "**/libagora_ai_echo_cancellation_ll_extension.so",
                "**/libagora_ai_noise_suppression_ll_extension.so",
                "**/libagora_screen_capture_extension.so",
                "**/libagora_face_capture_extension.so",
                "**/libagora_face_detection_extension.so",
                "**/libagora_face_tracking_extension.so",
                "**/libagora_segmentation_extension.so",
                "**/libagora_lip_sync_extension.so"
            )
        }
    }

    // Lint configuration for stricter code quality checks
    lint {
        // Abort build on errors in release builds
        abortOnError = true
        // Treat warnings as errors in CI/release (set to false for local dev)
        warningsAsErrors = false
        // Check all issues, not just those in the default set
        checkAllWarnings = true
        // Generate HTML report
        htmlReport = true
        // Avoid calling .get() or access properties during configuration to prevent eager evaluation
        htmlOutput = file("${project.projectDir}/build/reports/lint-results.html")
        // Baseline for gradual adoption
        baseline = file("lint-baseline.xml")
    }
}

flutter {
    source = "../.."
}

// Fix for Flutter tool not finding APKs - copies APK to where Flutter tool expects it
// Handles both debug and release builds
android.applicationVariants.all {
    val variant = this
    val variantName = variant.name
    val capitalizedVariantName = variantName.replaceFirstChar { it.uppercase() }
    val taskName = "copy${capitalizedVariantName}ApkForFlutter"

    tasks.register<Copy>(taskName) {
        group = "flutter"
        description = "Copies ${variantName} APK for Flutter tool compatibility"

        // Use the standard Android APK output directory
        from("${project.buildDir}/outputs/apk/${variantName}")
        into("${project.buildDir}/outputs/flutter-apk/")

        // Also copy to the root build directory where Flutter tool expects it
        doLast {
            val sourceFlutterApkDir = file("${project.buildDir}/outputs/flutter-apk/")
            val targetFlutterApkDir = file("${rootProject.projectDir}/../build/app/outputs/flutter-apk/")
            targetFlutterApkDir.mkdirs()

            val apkFiles = sourceFlutterApkDir.listFiles()?.filter { it.name.endsWith(".apk") }
            if (apkFiles != null && apkFiles.isNotEmpty()) {
                // For release builds with ABI splits, find arm64 and copy as generic
                val arm64Apk = apkFiles.find {
                    it.name.contains("arm64-v8a") && it.name.endsWith(".apk")
                }
                if (arm64Apk != null && arm64Apk.exists()) {
                    val genericApk = File(sourceFlutterApkDir, "app-${variantName}.apk")
                    arm64Apk.copyTo(genericApk, overwrite = true)
                    println("✓ Created android/app/build/outputs/flutter-apk/app-${variantName}.apk")
                }

                // Copy all APKs to root build directory
                apkFiles.forEach { apk ->
                    apk.copyTo(File(targetFlutterApkDir, apk.name), overwrite = true)
                }
                if (arm64Apk != null) {
                    arm64Apk.copyTo(File(targetFlutterApkDir, "app-${variantName}.apk"), overwrite = true)
                    println("✓ Created build/app/outputs/flutter-apk/app-${variantName}.apk")
                } else if (apkFiles.size == 1) {
                    // For debug builds (no split), copy the single APK with standard name
                    apkFiles.first().copyTo(File(targetFlutterApkDir, "app-${variantName}.apk"), overwrite = true)
                    println("✓ Created build/app/outputs/flutter-apk/app-${variantName}.apk")
                }
            }
        }
    }

    // Make this task run after the assemble task
    tasks.named("assemble${capitalizedVariantName}") {
        finalizedBy(taskName)
    }
}
