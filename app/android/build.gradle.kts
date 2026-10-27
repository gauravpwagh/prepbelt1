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

// receive_sharing_intent 1.9.0 is written for AGP 9: its build file uses
// `kotlin { }` without applying the Kotlin plugin, and compileSdk 37. Newer
// Flutter Gradle tooling copes; Flutter 3.41 with AGP 8.11 does not. Apply
// Kotlin (a no-op where it is already applied) and compile it against the
// app's SDK 36; its code only uses APIs up to 33.
subprojects {
    if (name == "receive_sharing_intent") {
        pluginManager.withPlugin("com.android.library") {
            pluginManager.apply("org.jetbrains.kotlin.android")
        }
        afterEvaluate {
            (extensions.getByName("android") as com.android.build.gradle.BaseExtension)
                .compileSdkVersion(36)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
