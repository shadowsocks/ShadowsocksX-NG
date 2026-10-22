import Foundation
import XCTest

@testable import ShadowsocksX_NG2

/// SIP002 ss:// 编解码往返，覆盖插件同构与特殊字符。
/// base64 期望值用系统 `base64` 独立计算，不依赖被测代码。
final class SsUriTests: XCTestCase {
  // MARK: - 解码：SIP002 形态

  func testDecodeSIP002Minimal() throws {
    let uri = "ss://YWVzLTI1Ni1nY206cGFzc3dvcmQxMjM=@203.0.113.7:8388"
    let decoded = try SsUri.decode(uri)
    XCTAssertEqual(decoded.method, "aes-256-gcm")
    XCTAssertEqual(decoded.password, "password123")
    XCTAssertEqual(decoded.host, "203.0.113.7")
    XCTAssertEqual(decoded.port, 8388)
    XCTAssertNil(decoded.pluginProgram)
    XCTAssertNil(decoded.pluginOptions)
    XCTAssertNil(decoded.remark)
  }

  func testDecodeSIP002WithTrailingSlashAndRemark() throws {
    let uri = "ss://cmM0LW1kNTpwYXNzd29yZA==@192.168.100.1:8888/#Example1"
    let decoded = try SsUri.decode(uri)
    XCTAssertEqual(decoded.method, "rc4-md5")
    XCTAssertEqual(decoded.password, "password")
    XCTAssertEqual(decoded.remark, "Example1")
  }

  func testDecodeSIP002PluginQuery() throws {
    // 官方示例形态：query 值整体百分号编码（: = → %3B %3A %3D）。
    let uri =
      "ss://cmM0LW1kNTpwYXNzd29yZA==@192.168.100.1:8888/"
      + "?plugin=obfs-local%3Bobfs%3Dhttp%3Bobfs-host%3Dexample.com#Example1"
    let decoded = try SsUri.decode(uri)
    XCTAssertEqual(decoded.pluginProgram, "obfs-local")
    XCTAssertEqual(decoded.pluginOptions, "obfs=http;obfs-host=example.com")
  }

  func testDecodeSIP002PluginWithoutOptions() throws {
    let uri = "ss://YWVzLTI1Ni1nY206cGFzc3dvcmQxMjM=@203.0.113.7:8388/?plugin=v2ray-plugin"
    let decoded = try SsUri.decode(uri)
    XCTAssertEqual(decoded.pluginProgram, "v2ray-plugin")
    XCTAssertNil(decoded.pluginOptions)
  }

  func testDecodeSIP002EmptyPluginValueIsNoPlugin() throws {
    let uri = "ss://YWVzLTI1Ni1nY206cGFzc3dvcmQxMjM=@203.0.113.7:8388/?plugin="
    let decoded = try SsUri.decode(uri)
    XCTAssertNil(decoded.pluginProgram)
  }

  func testDecodeSIP002IPv6Host() throws {
    let uri = "ss://YWVzLTI1Ni1nY206cGFzc3dvcmQxMjM=@[2001:db8::1]:8388"
    let decoded = try SsUri.decode(uri)
    XCTAssertEqual(decoded.host, "2001:db8::1")
    XCTAssertEqual(decoded.port, 8388)
  }

  /// AEAD-2022 客户端按 SIP022 用百分号编码明文 userinfo。
  func testDecodeSIP022PlaintextUserInfo() throws {
    let uri =
      "ss://2022-blake3-aes-256-gcm:hmackyEyXXXXXXXXXXXXXXXXXXXw%3D%3D@203.0.113.7:8388"
    let decoded = try SsUri.decode(uri)
    XCTAssertEqual(decoded.method, "2022-blake3-aes-256-gcm")
    XCTAssertEqual(decoded.password, "hmackyEyXXXXXXXXXXXXXXXXXXXw==")
  }

  func testDecodeLegacyBase64Form() throws {
    let uri = "ss://YWVzLTI1Ni1nY206dGVzdEAyMDMuMC4xMTMuNzo4Mzg4#香港 01"
    let decoded = try SsUri.decode(uri)
    XCTAssertEqual(decoded.method, "aes-256-gcm")
    XCTAssertEqual(decoded.password, "test")
    XCTAssertEqual(decoded.host, "203.0.113.7")
    XCTAssertEqual(decoded.port, 8388)
    XCTAssertEqual(decoded.remark, "香港 01")
  }

  /// Legacy 密码为明文：凭据必须在最后一个 @ 处切分，密码中的 `@` 与 `:` 原样保留。
  func testDecodeLegacyPasswordContainingAtAndColon() throws {
    let uri = "ss://YWVzLTI1Ni1nY206dEBzdDpwd0AyMDMuMC4xMTMuNzo4Mzg4"
    let decoded = try SsUri.decode(uri)
    XCTAssertEqual(decoded.method, "aes-256-gcm")
    XCTAssertEqual(decoded.password, "t@st:pw")
    XCTAssertEqual(decoded.host, "203.0.113.7")
    XCTAssertEqual(decoded.port, 8388)
  }

  func testDecodeToleratesMissingBase64PaddingAndURLSafeAlphabet() throws {
    // `chacha20-ietf-poly1305:pw` 的 base64 末尾 padding 常被省略。
    let padded = Data("chacha20-ietf-poly1305:pw".utf8).base64EncodedString()
    let unpadded = padded.replacingOccurrences(of: "=", with: "")
    let uriSafe = unpadded.replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
    let decoded = try SsUri.decode("ss://\(uriSafe)@203.0.113.7:8388")
    XCTAssertEqual(decoded.method, "chacha20-ietf-poly1305")
    XCTAssertEqual(decoded.password, "pw")
  }

  func testDecodeTrimsSurroundingWhitespace() throws {
    let decoded = try SsUri.decode("  ss://YWVzLTI1Ni1nY206cGFzc3dvcmQxMjM=@203.0.113.7:8388\n")
    XCTAssertEqual(decoded.port, 8388)
  }

  // MARK: - 解码失败

  func testDecodeRejectsNonSsScheme() {
    XCTAssertThrowsError(try SsUri.decode("http://example.com")) { error in
      XCTAssertEqual(error as? SsUriError, .notSsUri)
    }
    XCTAssertThrowsError(try SsUri.decode("plain text")) { error in
      XCTAssertEqual(error as? SsUriError, .notSsUri)
    }
  }

  func testDecodeRejectsMissingPort() {
    XCTAssertThrowsError(try SsUri.decode("ss://YWVz@203.0.113.7")) { error in
      guard case SsUriError.malformed = error else { return XCTFail("\(error)") }
    }
  }

  func testDecodeRejectsInvalidPort() {
    XCTAssertThrowsError(try SsUri.decode("ss://YWVz@203.0.113.7:notaport"))
    XCTAssertThrowsError(try SsUri.decode("ss://YWVz@203.0.113.7:0"))
    XCTAssertThrowsError(try SsUri.decode("ss://YWVz@203.0.113.7:70000"))
  }

  func testDecodeRejectsGarbagePayload() {
    XCTAssertThrowsError(try SsUri.decode("ss://!!!not-base64@203.0.113.7:8388"))
    XCTAssertThrowsError(try SsUri.decode("ss://!!!!"))
  }

  // MARK: - 编码

  func testEncodeCanonicalSIP002() {
    let uri = SsUri(
      method: "aes-256-gcm", password: "password123", host: "203.0.113.7", port: 8388)
    // 生态惯例（Outline / shadowsocks-rust）：url-safe 字母表、无 padding。
    XCTAssertEqual(uri.encode(), "ss://YWVzLTI1Ni1nY206cGFzc3dvcmQxMjM@203.0.113.7:8388")
  }

  func testEncodeBase64URLAlphabetWithoutPadding() {
    // 含 `+`/`/` 的明文：编码必须落在 url-safe 字母表且无 padding。
    let uri = SsUri(method: "aes-128-gcm", password: "??>>", host: "203.0.113.7", port: 1)
    let encoded = uri.encode()
    let userInfo = String(encoded.dropFirst("ss://".count).prefix { $0 != "@" })
    XCTAssertFalse(userInfo.contains("+"))
    XCTAssertFalse(userInfo.contains("/"))
    XCTAssertFalse(userInfo.contains("="))
  }

  func testEncodePluginUsesPercentEncoding() {
    let uri = SsUri(
      method: "rc4-md5", password: "password", host: "192.168.100.1", port: 8888,
      pluginProgram: "obfs-local", pluginOptions: "obfs=http;obfs-host=example.com",
      remark: "Example1")
    XCTAssertEqual(
      uri.encode(),
      "ss://cmM0LW1kNTpwYXNzd29yZA@192.168.100.1:8888"
        + "/?plugin=obfs-local%3Bobfs%3Dhttp%3Bobfs-host%3Dexample.com#Example1")
  }

  func testEncodeSIP022UsesPlaintextPercentEncodedUserInfo() {
    let uri = SsUri(
      method: "2022-blake3-aes-256-gcm", password: "hmackyEyXXXXXXXXXXXXXXXXXXXw==",
      host: "203.0.113.7", port: 8388)
    XCTAssertEqual(
      uri.encode(),
      "ss://2022-blake3-aes-256-gcm:hmackyEyXXXXXXXXXXXXXXXXXXXw%3D%3D@203.0.113.7:8388")
  }

  func testEncodeIPv6Rebrackets() {
    let uri = SsUri(method: "aes-256-gcm", password: "p", host: "2001:db8::1", port: 8388)
    XCTAssertTrue(uri.encode().hasSuffix("@[2001:db8::1]:8388"))
  }

  // MARK: - 往返同构

  func testRoundTripCorpusPreservesAllFields() throws {
    let corpus: [SsUri] = [
      SsUri(method: "aes-256-gcm", password: "password123", host: "203.0.113.7", port: 8388),
      SsUri(
        method: "rc4-md5", password: "password", host: "192.168.100.1", port: 8888,
        remark: "Example1"),
      // 特殊字符：密码含 URI 结构字符、空白、中文。
      SsUri(
        method: "chacha20-ietf-poly1305", password: "p@ss:wo/rd#1&=%+ 空格",
        host: "203.0.113.7", port: 8388, remark: "香港 01 #备注"),
      // 插件同构：name;opts 原样保留（含 `=`、`:`、`/`、`%`、中文）。
      SsUri(
        method: "aes-256-gcm", password: "p", host: "203.0.113.7", port: 8388,
        pluginProgram: "v2ray-plugin",
        pluginOptions: "mode=websocket;path=/wss%20x;host=例.com;loglevel=warn"),
      // 插件参数含 URI 分隔符与 `&`、`;`（透传形态）。
      SsUri(
        method: "aes-256-gcm", password: "p", host: "203.0.113.7", port: 8388,
        pluginProgram: "v2ray-plugin", pluginOptions: "mux=1&t=11;path=/a;b"),
      // 仅有插件名、无参数。
      SsUri(
        method: "aes-256-gcm", password: "p", host: "203.0.113.7", port: 8388,
        pluginProgram: "v2ray-plugin"),
      // SIP022 明文 userinfo 往返。
      SsUri(
        method: "2022-blake3-aes-256-gcm", password: "hmackyEyXXXXXXXXXXXXXXXXXXXw==",
        host: "203.0.113.7", port: 8388),
      // IPv6 往返。
      SsUri(method: "aes-256-gcm", password: "p", host: "2001:db8::1", port: 9101),
    ]
    for original in corpus {
      let decoded = try SsUri.decode(original.encode())
      XCTAssertEqual(decoded, original, "往返失真：\(original)")
    }
  }

  func testDecodeRejectsEmptyPassword() {
    let encoded = SsUri(
      method: "aes-256-gcm", password: "", host: "203.0.113.7", port: 8388
    ).encode()
    XCTAssertThrowsError(try SsUri.decode(encoded))
  }

  func testCanonicalInputSurvivesDecodeEncodeVerbatim() throws {
    let canonical =
      "ss://cmM0LW1kNTpwYXNzd29yZA@192.168.100.1:8888"
      + "/?plugin=obfs-local%3Bobfs%3Dhttp%3Bobfs-host%3Dexample.com#Example1"
    XCTAssertEqual(try SsUri.decode(canonical).encode(), canonical)
  }

  /// 密码与插件参数里的 `@`/`#`/`?`/`&` 不得破坏 URI 结构。
  func testStructureCharactersInSecretsStayOpaque() throws {
    let hostile = SsUri(
      method: "aes-256-gcm",
      password: "a@b#c?d&e=f g/h;i%3B",
      host: "203.0.113.7", port: 8388,
      pluginProgram: "v2ray-plugin",
      pluginOptions: "path=/ws?x=1;host=h@ck#er",
      remark: "名#字?1")
    let decoded = try SsUri.decode(hostile.encode())
    XCTAssertEqual(decoded, hostile)
  }
}
