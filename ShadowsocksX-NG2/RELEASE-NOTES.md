# Unreleased

- Rule mode now offers three named presets: Direct for Mainland China, Proxy GFWList Targets Only, and Proxy Mainland China Targets. Existing routing choices map to their equivalent presets.
- Each preset has its own custom rules and disabled rules. **Existing custom rules and rule enablement/disablement settings are not migrated.** Recreate these settings in the appropriate preset. Old files are retained.
- Manage and test each preset independently on the Rules page. Select the preset used for routing in the proxy controls.
- The Mainland China proxy preset requires a suitable user-provided Mainland China exit server. Built-in coverage is incomplete and does not guarantee access to region-restricted content.

## 简体中文

- 规则模式提供“中国大陆目标直连”“仅GFW列表内目标代理”“中国大陆目标代理”三项预设。已有路由选择映射到等价预设。
- 各预设独立保存自定义规则和停用选择。**旧自定义规则、旧规则启用／禁用配置均不迁移。** 请在对应预设中重新配置；旧文件保留。
- 规则页可独立管理、离线测试各预设；实际使用的预设在代理控制入口选择。
- 中国大陆目标代理需要用户自行提供合适的中国大陆出口。内置集合不保证覆盖所有目标，也不承诺地区限制内容可访问。
