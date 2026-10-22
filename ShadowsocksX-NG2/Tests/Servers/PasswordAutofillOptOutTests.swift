import AppKit
import SwiftUI
import Testing

@testable import ShadowsocksX_NG2

/// 系统对安全输入框默认提供「密码自动填充」，`textContentType(nil)` 只清字段
/// 语义、关不掉它；生产代码改字段级私有开关 `_setPasswordAutofillEnabled:`
/// （`PasswordAutofillOptOut` 探针认领同帧文本框后经 KVC 写入）。
///
/// 这些用例固定认领范围：只关密码列自己的文本框，同一表单的其他输入框保持
/// 系统默认。私有开关哪天消失，用例失败即提示重做这个缝，而不是静默回退。
@MainActor
struct PasswordAutofillOptOutTests {
  @Test
  func securePasswordFieldOptsOutWithoutTouchingNeighbours() async throws {
    let fields = ServerFormFields.newForm()
    let hosted = await Self.hostGrid(fields)

    let textFields = Self.textFields(in: hosted.host)
    let secure = textFields.filter { $0 is NSSecureTextField }
    #expect(secure.count == 1, "密码列是全表单唯一的安全输入框")
    #expect(Self.disabledAutofillFields(in: hosted.host).count == 1, "只允许关掉密码列")
    #expect(Self.passwordAutofillEnabled(try #require(secure.first)) == false)
    #expect(
      textFields.filter { !($0 is NSSecureTextField) }
        .allSatisfy { Self.passwordAutofillEnabled($0) == true },
      "名称/服务器地址/端口等字段保持系统默认")
  }

  @Test
  func visiblePasswordBranchOptsOutToo() async throws {
    let fields = ServerFormFields.newForm()
    fields.showPassword = true
    let hosted = await Self.hostGrid(fields)

    let textFields = Self.textFields(in: hosted.host)
    #expect(textFields.allSatisfy { !($0 is NSSecureTextField) }, "明文分支不渲染安全输入框")
    #expect(Self.disabledAutofillFields(in: hosted.host).count == 1, "只允许关掉密码列")
  }

  @Test
  func togglingPasswordVisibilityKeepsAutofillOff() async throws {
    let fields = ServerFormFields.newForm()
    let hosted = await Self.hostGrid(fields)
    #expect(Self.disabledAutofillFields(in: hosted.host).count == 1)

    // 明文/密文切换会换掉承载的文本框，认领必须跟着新实例重做。
    fields.showPassword = true
    await Self.settle(hosted.host)
    #expect(Self.textFields(in: hosted.host).allSatisfy { !($0 is NSSecureTextField) })
    #expect(Self.disabledAutofillFields(in: hosted.host).count == 1)

    fields.showPassword = false
    await Self.settle(hosted.host)
    #expect(Self.textFields(in: hosted.host).filter { $0 is NSSecureTextField }.count == 1)
    #expect(Self.disabledAutofillFields(in: hosted.host).count == 1)
  }

  // MARK: 夹具

  /// 复用生产表单：探针、栅格与字段实现都在真实布局里跑一遍。
  private struct GridHarness: View {
    @ObservedObject var fields: ServerFormFields
    @FocusState private var fieldFocus: ServerFormField?

    var body: some View {
      ServerFormFieldsGrid(
        fields: fields, plugin: nil, isEditable: true, fieldFocus: $fieldFocus)
    }
  }

  /// 探针在窗口坐标里认领文本框：无窗口的 hosting view 不构成呈现，认领会落空，
  /// 因此夹具必须给一个离屏窗口（不呈现、不抢 key）。
  private static func hostGrid(
    _ fields: ServerFormFields
  ) async -> (window: NSWindow, host: NSHostingView<GridHarness>) {
    let host = NSHostingView(rootView: GridHarness(fields: fields))
    host.frame = NSRect(x: 0, y: 0, width: 560, height: 720)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 560, height: 720),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    await settle(host)
    return (window, host)
  }

  /// 让 SwiftUI 的渲染事务与探针的布局回调都跑完再断言。
  private static func settle(_ host: NSHostingView<GridHarness>) async {
    for _ in 0..<2 {
      await Task { @MainActor in }.value
      host.layoutSubtreeIfNeeded()
    }
  }

  private static func textFields(in view: NSView) -> [NSTextField] {
    if let field = view as? NSTextField { return [field] + view.subviews.flatMap(textFields) }
    return view.subviews.flatMap(textFields)
  }

  private static func disabledAutofillFields(in view: NSView) -> [NSTextField] {
    textFields(in: view).filter { passwordAutofillEnabled($0) == false }
  }

  /// BOOL 返回值不能走 `perform`（会被当成对象返回值），只能取 IMP 直调。
  private static func passwordAutofillEnabled(_ field: NSTextField) -> Bool? {
    let selector = NSSelectorFromString("_isPasswordAutofillEnabled")
    guard let method = class_getInstanceMethod(type(of: field), selector) else { return nil }
    typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
    return unsafeBitCast(method_getImplementation(method), to: Getter.self)(field, selector)
  }
}
