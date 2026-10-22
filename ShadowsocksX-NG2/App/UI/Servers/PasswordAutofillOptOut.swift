import AppKit
import SwiftUI

/// 关掉系统给密码输入框的「密码自动填充」入口。
///
/// SwiftUI 的 `SecureField` 在 macOS 上由 `NSSecureTextField` 承载；系统对安全
/// 输入框默认提供钥匙串/密码 App 的自动填充入口。`textContentType(nil)` 只清掉
/// 字段语义（实测底层字段 `contentType` 已是 nil），关不掉入口；AppKit 没有公开
/// 开关，唯一开关是字段级的私有 `_setPasswordAutofillEnabled:`（默认开）。这里在
/// 探针认领到的文本框上按需调用它：方法不存在（系统换实现）时保持系统默认
/// 行为，不做替代实现，也不让 KVC 抛异常。
///
/// 用法：贴在密码控件（`Group { TextField / SecureField }`）的 `.background(...)`
/// 上。探针与控件同帧，据此在祖先里认领同帧的文本框，因此同一表单里的其他
/// 输入框不会被误伤。
struct PasswordAutofillOptOut: NSViewRepresentable {
  func makeNSView(context: Context) -> ProbeView {
    ProbeView()
  }

  func updateNSView(_ view: ProbeView, context: Context) {
    view.disablePasswordAutofill()
  }

  /// 背景探针：由 `.background` 撑满密码控件，据此认领承载控件的文本框。
  final class ProbeView: NSView {
    /// 已处理过的文本框：明文/密文切换会换成新实例，换实例即重新处理。
    private weak var claimedField: NSTextField?

    private static let setterSelector = NSSelectorFromString("_setPasswordAutofillEnabled:")

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      disablePasswordAutofill()
    }

    override func setFrameSize(_ newSize: NSSize) {
      super.setFrameSize(newSize)
      disablePasswordAutofill()
    }

    override func setFrameOrigin(_ newOrigin: NSPoint) {
      super.setFrameOrigin(newOrigin)
      disablePasswordAutofill()
    }

    func disablePasswordAutofill() {
      let target = convert(bounds, to: nil)
      guard window != nil, !target.isEmpty else { return }
      guard let field = Self.field(overlapping: target, from: superview) else { return }
      guard field !== claimedField else { return }
      claimedField = field
      guard field.responds(to: Self.setterSelector) else { return }
      field.setValue(false, forKey: "passwordAutofillEnabled")
    }

    /// 逐层向上找第一个含候选文本框的祖先视图。按交叠面积认领而不是逐边
    /// 相等：探针与控件同帧，取整差异不应该让认领落空。
    private static func field(overlapping target: NSRect, from view: NSView?) -> NSTextField? {
      var ancestor = view
      while let current = ancestor {
        if let match = bestMatch(in: current, target: target) { return match.field }
        ancestor = current.superview
      }
      return nil
    }

    private static func bestMatch(
      in view: NSView, target: NSRect
    ) -> (field: NSTextField, area: CGFloat)? {
      var best: (field: NSTextField, area: CGFloat)?
      if let field = view as? NSTextField, field.window != nil,
        let area = intersectionArea(of: field, with: target), area > 0
      {
        best = (field, area)
      }
      for subview in view.subviews {
        guard let candidate = bestMatch(in: subview, target: target) else { continue }
        if candidate.area > (best?.area ?? 0) { best = candidate }
      }
      return best
    }

    private static func intersectionArea(of field: NSTextField, with target: NSRect) -> CGFloat? {
      let rect = field.convert(field.bounds, to: nil)
      let intersection = rect.intersection(target)
      guard !intersection.isNull else { return nil }
      return intersection.width * intersection.height
    }
  }
}
