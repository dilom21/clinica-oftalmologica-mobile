# Reglas de ProGuard requeridas por flutter_stripe (Stripe Android SDK).
# Se aplican solo cuando la minificación está habilitada en release.

-dontwarn com.stripe.android.pushProvisioning.**
-dontwarn com.google.android.gms.tapandpay.**
-dontwarn kotlinx.parcelize.Parceler$DefaultImpls
-dontwarn kotlinx.parcelize.Parceler
-dontwarn kotlinx.parcelize.Parcelize

# Keep Stripe classes
-keep class com.stripe.** { *; }
