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
// screen_protector relies on AGP's built-in Kotlin, which this project has switched off (android.builtInKotlin=false, as
// firebase_core / flutter_webrtc still apply the Kotlin plugin themselves): without this its Kotlin sources are never
// compiled and GeneratedPluginRegistrant fails with "cannot find symbol ScreenProtectorPlugin".
subprojects {
    if (name == "screen_protector") {
        plugins.withId("com.android.library") { pluginManager.apply("org.jetbrains.kotlin.android") }
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
