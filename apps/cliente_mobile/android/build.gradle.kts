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

// Third-party Android modules (e.g. coinbase_wallet_sdk, pulled in through the
// Reown/WalletConnect dependency tree) pin old compileSdk values such as 31.
// Runner images and local SDKs no longer ship those platform packages, so any
// build resolves a missing "platforms;android-31" and fails. Force every
// Android subproject to compile against the SDK level the app itself uses;
// raising compileSdk keeps these modules source-compatible and makes the
// build independent of which platforms the environment happens to carry.
fun Project.alignCompileSdkWithApp() {
    afterEvaluate {
        val appAndroid = project(":app").extensions.findByName("android")
        val appCompileSdkVersion = appAndroid
            ?.let { it as? com.android.build.gradle.AppExtension }
            ?.compileSdkVersion
        val androidExtension = extensions.findByName("android")
        if (appCompileSdkVersion != null && androidExtension != null) {
            (androidExtension as com.android.build.gradle.BaseExtension)
                .compileSdkVersion(appCompileSdkVersion)
        }
    }
}

subprojects {
    // evaluationDependsOn(":app") above evaluates :app while the root script
    // still runs, so registering afterEvaluate for it here would throw. The
    // app module already compiles with its own SDK level.
    if (path != ":app") {
        alignCompileSdkWithApp()
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
