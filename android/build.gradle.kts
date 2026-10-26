import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// flutter_stripe 14.1.0 arrastra `stripe-android-issuing-push-provisioning:1.3.0`,
// que declara `com.google.android.gms:play-services-tapandpay:18.8.0` SOLO en el
// classpath de lint. Ese artefacto no está publicado en Google Maven, así que
// `assembleRelease` aborta en `:stripe_android:lintVitalAnalyzeRelease` antes de
// generar el APK ("Could not find ... play-services-tapandpay:18.8.0").
// Es un análisis estático del plugin y no participa en el APK: se desactivan
// únicamente las tareas lintVital del plugin Stripe y se conserva el lint del
// resto del proyecto.
// El JDK que ejecuta Gradle es más nuevo que el target 17 del proyecto.
// stripe_android hereda ese JDK en Kotlin y el build se corta por la
// diferencia con compileDebugJavaWithJavac (17).
subprojects {
    tasks.withType<KotlinCompile>().configureEach {
        compilerOptions {
            jvmTarget.set(JvmTarget.JVM_17)
        }
    }
}

subprojects {
    if (name == "stripe_android") {
        tasks.matching { it.name.startsWith("lintVital") }.configureEach {
            enabled = false
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
