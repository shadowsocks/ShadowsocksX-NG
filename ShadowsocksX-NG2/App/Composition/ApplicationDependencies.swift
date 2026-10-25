import AppKit

/// 组合根依赖集（仅生产形态）：单测不再以本 app 为宿主（去宿主化，ADR 0021），
/// 装配永远面向真实存储、系统服务与用户默认域。
@MainActor
struct ApplicationDependencies {
  let catalogFileStore: CatalogFileStore
  let activationFileStore: ActivationStateFileStore
  let runtimeFileStore: RuntimeFileStore
  let listeningStore: ProxyListeningFileStore
  let settingsRestore: RestoredProxyRuntimeSettings
  let legacyImportService: LegacyImportService
  let launchAgent: LaunchAgentControlling
  let loginService: LaunchAtLoginControlling
  let silentLaunchStore: SilentLaunchStore
  let textClipboard: any TextClipboard
  let imageClipboard: any ImageClipboard
  let diagnosticReportExporter: any DiagnosticReportExporter
  let configurationGroupFileExporter: any ConfigurationGroupFileExporter
  let qrImageSaver: any QrImageSaver

  static func make() -> ApplicationDependencies {
    let listeningStore = ProxyListeningFileStore()
    let listening = ProxyListeningStartup.load(
      store: listeningStore, presentReset: ProxyListeningResetAlert.present)
    let library = ServerLibraryStorage()
    let catalogFileStore = CatalogFileStore(
      fileURL: CatalogFileStore.defaultFileURL(), library: library)
    let restoredSettings = RestoredProxyRuntimeSettings(
      settings: ProxyRuntimeSettings(
        listen: listening, preferences: ProxyControlPreferences()),
      unreadableError: nil)
    return ApplicationDependencies(
      catalogFileStore: catalogFileStore,
      activationFileStore: ActivationStateFileStore(
        fileURL: ActivationStateFileStore.defaultFileURL()),
      runtimeFileStore: RuntimeFileStore(),
      listeningStore: listeningStore,
      settingsRestore: restoredSettings,
      legacyImportService: LegacyImportService(
        catalogStore: catalogFileStore),
      launchAgent: SMAppLaunchAgentService(),
      loginService: SMAppLaunchAtLoginService(),
      silentLaunchStore: SilentLaunchStore(),
      textClipboard: AppKitTextClipboard(),
      imageClipboard: AppKitImageClipboard(),
      diagnosticReportExporter: AppKitDiagnosticReportExporter(),
      configurationGroupFileExporter: AppKitConfigurationGroupFileExporter(),
      qrImageSaver: AppKitQrImageSaver())
  }

}
