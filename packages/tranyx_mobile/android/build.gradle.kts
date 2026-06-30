// Fix missing consumer-rules.pro in coinbase_wallet_sdk package
val pubCachePath = System.getenv("PUB_CACHE") ?: "${System.getProperty("user.home")}/.pub-cache"
val pubCacheDir = java.io.File(pubCachePath)
if (pubCacheDir.exists()) {
    listOf("hosted/pub.dev", "hosted/pub.dartlang.org").forEach { hostPath ->
        val hostDir = java.io.File(pubCacheDir, hostPath)
        if (hostDir.exists()) {
            hostDir.listFiles()?.forEach { pkgDir ->
                if (pkgDir.name.startsWith("coinbase_wallet_sdk-")) {
                    val androidDir = java.io.File(pkgDir, "android")
                    if (androidDir.exists()) {
                        val consumerRules = java.io.File(androidDir, "consumer-rules.pro")
                        if (!consumerRules.exists()) {
                            try {
                                consumerRules.createNewFile()
                                println("Auto-created missing consumer-rules.pro in ${pkgDir.name}")
                            } catch (e: Exception) {
                                // Ignore
                            }
                        }
                    }
                }
            }
        }
    }
}

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

    afterEvaluate {
        val android = project.extensions.findByName("android")
        if (android != null) {
            val baseExtension = android as? com.android.build.gradle.BaseExtension
            baseExtension?.run {
                compileSdkVersion(36)
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
