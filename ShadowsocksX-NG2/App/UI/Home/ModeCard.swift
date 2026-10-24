import SwiftUI

/// 「代理模式」卡：可用模式切换（Domain 单点策略投影）+ 规则子选项 + 模式说明。
struct ModeCard: View {
  @ObservedObject var control: ProxyControlWorkflow

  var body: some View {
    HomeCard(
      title: String(localized: "代理路由模式"),
      subtitle: nil,
      trailing: { EmptyView() },
      content: {
        VStack(alignment: .leading, spacing: 14) {
          Picker("代理模式", selection: modeBinding) {
            ForEach(control.snapshot.availableModes, id: \.self) { mode in
              Text(mode.label).tag(mode)
            }
          }
          .pickerStyle(.segmented)
          .labelsHidden()
          .frame(maxWidth: 480, alignment: .leading)
          if control.snapshot.proxyMode == .rule {
            HStack(spacing: 8) {
              Text("规则预设")
              Picker("规则预设", selection: rulePresetBinding) {
                ForEach(RulePreset.allCases, id: \.self) { action in
                  Text(action.label).tag(action)
                }
              }
              .pickerStyle(.segmented)
              .labelsHidden()
              .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
          Text(modeDescription(control.snapshot.proxyMode))
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
      })
  }

  private var modeBinding: Binding<ProxyMode> {
    Binding(
      get: { control.snapshot.proxyMode },
      set: { mode in
        Task { await control.setProxyMode(mode) }
      })
  }

  private var rulePresetBinding: Binding<RulePreset> {
    Binding(
      get: { control.snapshot.rulePreset },
      set: { action in
        Task { await control.setRulePreset(action) }
      })
  }

  private func modeDescription(_ mode: ProxyMode) -> String {
    switch mode {
    case .rule:
      String(localized: "按内置规则在代理与直连间选择；未匹配目标走默认动作。")
    case .global:
      String(localized: "所有系统代理流量通过本地 SOCKS 与 HTTP 入口转发，不使用规则分流。")
    case .direct:
      String(localized: "通过本地 SOCKS 与 HTTP 入口直连，不使用 Shadowsocks 服务器。")
    }
  }
}
