import XCTest

@testable import ShadowsocksX_NG2

/// 二维码分享/识别互逆（验收：分享与添加互逆）。
final class QrCodeCodecTests: XCTestCase {
  func testGenerateThenDetectRoundTrip() throws {
    let payload = "ss://YWVzLTI1Ni1nY206cGFzc3dvcmQxMjM@203.0.113.7:8388#香港 01"
    let png = try QrCodeCodec.generatePNG(for: payload)
    let payloads = try QrCodeCodec.detectPayloads(in: png)
    XCTAssertEqual(payloads, [payload])
  }

  func testDetectHandlesChineseAndPluginPayload() throws {
    let payload =
      "ss://cmM0LW1kNTpwYXNzd29yZA@192.168.100.1:8888"
      + "/?plugin=obfs-local%3Bobfs%3Dhttp%3Bobfs-host%3Dexample.com#示例节点 🇭🇰"
    let png = try QrCodeCodec.generatePNG(for: payload)
    XCTAssertEqual(try QrCodeCodec.detectPayloads(in: png), [payload])
  }

  func testDetectGarbageDataThrows() {
    XCTAssertThrowsError(try QrCodeCodec.detectPayloads(in: Data("not an image".utf8)))
  }
}
