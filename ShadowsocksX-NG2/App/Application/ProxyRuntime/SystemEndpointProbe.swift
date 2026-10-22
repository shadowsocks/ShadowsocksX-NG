import Foundation

/// 端点探测缝：注入以便控制器单测（真实探测走 EndpointHealthProbe）。
protocol EndpointProbing: Sendable {
  func probe(host: String, port: Int, timeout: TimeInterval) -> EndpointHealthProbe.Outcome
}

struct SystemEndpointProbe: EndpointProbing {
  func probe(host: String, port: Int, timeout: TimeInterval) -> EndpointHealthProbe.Outcome {
    EndpointHealthProbe.probe(host: host, port: port, timeout: timeout)
  }
}
