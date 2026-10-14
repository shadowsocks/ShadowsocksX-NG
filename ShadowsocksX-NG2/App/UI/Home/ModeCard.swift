import SwiftUI

/// 「代理模式」卡：可用模式切换（Domain 单点策略投影）+ 规则子选项 + 模式说明。
struct ModeCard: View {
  @ObservedObject var control: ProxyControlWorkflow

  var body: some View {
    HomeCard(
      title: "代理路由模式",
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
              Text("未匹配规则时")
              Picker("未匹配规则时", selection: ruleDefaultActionBinding) {
                ForEach(RuleDefaultAction.allCases, id: \.self) { action in
                  Text(action.label).tag(action)
                }
              }
              .pickerStyle(.segmented)
              .labelsHidden()
              .frame(maxWidth: 480, alignment: .leading)
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

  private var ruleDefaultActionBinding: Binding<RuleDefaultAction> {
    Binding(
      get: { control.snapshot.ruleDefaultAction },
      set: { action in
        Task { await control.setRuleDefaultAction(action) }
      })
  }

  private func modeDescription(_ mode: ProxyMode) -> String {
    switch mode {
    case .rule:
      "按内置规则在代理与直连间选择；未匹配目标走默认动作。"
    case .global:
      "所有系统代理流量通过本地 SOCKS 与 HTTP 入口转发，不使用规则分流。"
    case .direct:
      "通过本地 SOCKS 与 HTTP 入口直连，不使用 Shadowsocks 服务器。"
    }
  }
}
