import AppKit
import CoreImage
import Foundation
import Vision

/// 二维码编解码（分享生成二维码、识别二维码图片导入）。生成走
/// CoreImage `CIQRCodeGenerator`（纠错级 M），识别走 Vision 条码检测，返回
/// 全部文本负载。屏幕扫码明确不做，此处只处理静态图片。
enum QrCodeCodec {
  enum QrCodeError: Error, Equatable {
    /// 系统二维码滤镜产出为空（理论不可达，防御位）。
    case generationFailed
    /// 输入不是可解码的位图。
    case undecodableImage
  }

  /// 生成二维码 PNG 数据；`scale` 控制输出像素密度（每个模块的像素数）。
  static func generatePNG(for payload: String, scale: CGFloat = 8) throws -> Data {
    guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
      throw QrCodeError.generationFailed
    }
    filter.setValue(Data(payload.utf8), forKey: "inputMessage")
    filter.setValue("M", forKey: "inputCorrectionLevel")
    guard let output = filter.outputImage else { throw QrCodeError.generationFailed }
    let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let context = CIContext()
    guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
      throw QrCodeError.generationFailed
    }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    guard let png = rep.representation(using: .png, properties: [:]) else {
      throw QrCodeError.generationFailed
    }
    return png
  }

  /// 识别静态图片中的全部二维码/条码文本负载。
  static func detectPayloads(in imageData: Data) throws -> [String] {
    let request = VNDetectBarcodesRequest()
    let handler = VNImageRequestHandler(data: imageData, options: [:])
    do {
      try handler.perform([request])
    } catch {
      throw QrCodeError.undecodableImage
    }
    return request.results?.compactMap(\.payloadStringValue) ?? []
  }
}
