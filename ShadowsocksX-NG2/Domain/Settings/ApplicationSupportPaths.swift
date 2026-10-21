import Foundation

/// 应用支持目录按生命周期分类；路径计算不执行 I/O，也不迁移旧平铺文件。
struct ApplicationSupportPaths {
  static let current = ApplicationSupportPaths(
    rootURL: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("ShadowsocksX-NG2", isDirectory: true))

  let rootURL: URL

  var configurationDirectoryURL: URL {
    rootURL.appendingPathComponent("configuration", isDirectory: true)
  }

  var runtime: RuntimePaths {
    RuntimePaths(directoryURL: rootURL.appendingPathComponent("runtime", isDirectory: true))
  }

  var logsDirectoryURL: URL { rootURL.appendingPathComponent("logs", isDirectory: true) }
  var agentLogURL: URL { logsDirectoryURL.appendingPathComponent("agent.log") }
  var catalogFileURL: URL { configurationDirectoryURL.appendingPathComponent("catalog.age") }
  var proxyListeningFileURL: URL {
    configurationDirectoryURL.appendingPathComponent("proxy-listening.age")
  }
  var customRulesFileURL: URL {
    configurationDirectoryURL.appendingPathComponent("custom-rules.json")
  }
  var activationStateFileURL: URL {
    configurationDirectoryURL.appendingPathComponent("activation.json")
  }
  var pluginMappingFileURL: URL { configurationDirectoryURL.appendingPathComponent("plugins.json") }
}
