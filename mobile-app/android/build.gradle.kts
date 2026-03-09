// Force :app to evaluate first to prevent evaluation order issues caused by some plugins (like agora_rtc_engine).
evaluationDependsOn(":app")

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
