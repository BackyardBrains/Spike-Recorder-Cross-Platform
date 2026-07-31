# Add project specific ProGuard rules here.
# You can control the set of applied configuration files using the
# proguardFiles setting in build.gradle.

# Suppress warnings for missing Kotlin UUID classes
# These classes are referenced by kotlinx.serialization but may not be needed at runtime
-dontwarn kotlin.uuid.ExperimentalUuidApi
-dontwarn kotlin.uuid.Uuid$Companion
-dontwarn kotlin.uuid.Uuid

