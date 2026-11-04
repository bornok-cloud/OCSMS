plugins {
    id("com.google.gms.google-services") version "4.4.2" apply false
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
}

subprojects {
    val configureAndroid: (Project) -> Unit = { p ->
        val android = p.extensions.findByName("android")
        if (android != null) {
            try {
                val method = android.javaClass.methods.find {
                    it.name == "setCompileSdk" || it.name == "compileSdkVersion" || it.name == "setCompileSdkVersion"
                }
                method?.invoke(android, 36)
            } catch (e: Exception) {
                try {
                    val method = android.javaClass.methods.find {
                        it.name == "setCompileSdkVersion" || it.name == "compileSdkVersion"
                    }
                    method?.invoke(android, "android-36")
                } catch (e2: Exception) {
                    // ignore
                }
            }
        }
    }

    if (project.state.executed) {
        configureAndroid(project)
    } else {
        project.afterEvaluate {
            configureAndroid(project)
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}