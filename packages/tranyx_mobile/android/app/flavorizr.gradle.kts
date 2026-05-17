import com.android.build.gradle.AppExtension

val android = project.extensions.getByType(AppExtension::class.java)

android.apply {
    flavorDimensions("flavor-type")

    productFlavors {
        create("dev") {
            dimension = "flavor-type"
            applicationId = "com.terraph.tranyx.dev"
            resValue(type = "string", name = "app_name", value = "Tranyx Dev")
        }
        create("uat") {
            dimension = "flavor-type"
            applicationId = "com.terraph.tranyx.uat"
            resValue(type = "string", name = "app_name", value = "Tranyx UAT")
        }
        create("production") {
            dimension = "flavor-type"
            applicationId = "com.terraph.tranyx"
            resValue(type = "string", name = "app_name", value = "Tranyx")
        }
    }
}