import SwiftUI

struct ServerFormFieldsGrid: View {
  @ObservedObject var fields: ServerFormFields
  let plugin: PluginSectionState?
  let isEditable: Bool
  let fieldFocus: FocusState<ServerFormField?>.Binding
  var location: CreationLocationField?

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      row("名称") {
        TextField("名称", text: $fields.remark, prompt: Text("例如：香港服务器"))
          .textFieldStyle(.roundedBorder)
          .focused(fieldFocus, equals: .name)
          .disabled(!isEditable)
        fieldErrorLabel(.name)
      }
      if let location { location }
      ServerEndpointLayout {
        row("服务器地址") {
          TextField("服务器地址", text: $fields.address)
            .textFieldStyle(.roundedBorder)
            .focused(fieldFocus, equals: .address)
            .disabled(!isEditable)
          fieldErrorLabel(.address)
        }
        row("端口") {
          TextField("端口", text: $fields.portText)
            .textFieldStyle(.roundedBorder)
            .focused(fieldFocus, equals: .port)
            .disabled(!isEditable)
          fieldErrorLabel(.port)
        }
      }
      Picker("加密方式", selection: $fields.encryptionMethod) {
        ForEach(fields.methodChoices, id: \.self) { Text($0).tag($0) }
      }
      .disabled(!isEditable)
      row("密码") {
        HStack(spacing: 8) {
          Group {
            if fields.showPassword {
              TextField("密码", text: $fields.password)
                .background(PasswordAutofillOptOut())
            } else {
              SecureField("密码", text: $fields.password)
                .background(PasswordAutofillOptOut())
            }
          }
          .textFieldStyle(.roundedBorder)
          .textContentType(nil)
          .autocorrectionDisabled()
          .focused(fieldFocus, equals: .password)
          .disabled(!isEditable)
          Button {
            fields.showPassword.toggle()
          } label: {
            Image(systemName: fields.showPassword ? "eye.slash" : "eye")
          }
          .buttonStyle(.borderless)
          .help(fields.showPassword ? String(localized: "隐藏密码") : String(localized: "显示密码"))
          .accessibilityLabel(
            fields.showPassword ? String(localized: "隐藏密码") : String(localized: "显示密码"))
        }
        fieldErrorLabel(.password)
      }
      ServerPluginSection(
        selection: $fields.pluginChoice,
        options: fields.pluginOptions,
        plugin: plugin,
        isEditable: isEditable,
        optionsError: fields.fieldErrors[.pluginOptions],
        optionsFocus: fieldFocus)
    }
  }

  private func row<Content: View>(
    _ label: LocalizedStringKey, @ViewBuilder content: () -> Content
  ) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(label)
        .fixedSize()
      VStack(alignment: .leading, spacing: 6) {
        content()
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  /// 字段行内错误：只呈现字段、原因与上限，不回显字段内容。
  @ViewBuilder
  private func fieldErrorLabel(_ field: ServerFormField) -> some View {
    if let error = fields.fieldErrors[field] {
      Text(errorText(error, field: field))
        .font(.footnote)
        .foregroundStyle(.red)
    }
  }

  private func errorText(_ error: ServerFormFieldError, field: ServerFormField)
    -> LocalizedStringKey
  {
    switch error {
    case .missingName:
      return "请输入服务器名称"
    case .tooManyCharacters(let limit):
      switch field {
      case .name: return "名称最多 \(limit) 个字符"
      case .address: return "服务器地址最多 \(limit) 个字符"
      case .password: return "密码最多 \(limit) 个字符"
      case .port, .pluginOptions: return ""
      }
    case .tooManyBytes(let limit):
      return "插件参数最多 \(limit) 个字节"
    case .invalidPort:
      return "端口必须是 1–65535 的数字（最多 \(ServerFormFields.portDigitLimit) 位）"
    case .unfinishedPluginOptionRow:
      return ""
    }
  }
}

/// 扣除间距后按 4:1 分配地址和端口宽度，高度由字段自身决定。
private struct ServerEndpointLayout: Layout {
  private let spacing: CGFloat = 20

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = proposal.width ?? 480
    let unit = max(0, width - spacing) / 5
    let height =
      subviews.enumerated().map { index, view in
        view.sizeThatFits(ProposedViewSize(width: unit * (index == 0 ? 4 : 1), height: nil)).height
      }.max() ?? 0
    return CGSize(width: width, height: height)
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    let unit = max(0, bounds.width - spacing) / 5
    for (index, view) in subviews.enumerated() {
      view.place(
        at: CGPoint(x: bounds.minX + (index == 0 ? 0 : unit * 4 + spacing), y: bounds.minY),
        anchor: .topLeading,
        proposal: ProposedViewSize(width: unit * (index == 0 ? 4 : 1), height: nil))
    }
  }
}
