# 服务器表单密码字段关掉系统密码自动填充

Status: Accepted (2026-10-05)

服务器表单（新建表单与详情页表单共用同一栅格）的密码字段关掉 macOS 的密码自动填充入口：`PasswordAutofillOptOut` 背景探针按同帧认领承载密码控件的 `NSTextField`，再写字段级私有开关 `_setPasswordAutofillEnabled:`（KVC 键 `passwordAutofillEnabled`，`responds(to:)` 守卫）。

系统对 `NSSecureTextField` 默认提供钥匙串/密码 App 的自动填充入口，且不取决于字段语义：实测底层字段 `contentType` 已是 `nil`（既有 `.textContentType(nil)` 确实生效），入口照旧出现。AppKit 没有公开开关，唯一可用的是这个私有字段位。

## Considered options

- 只用 `.textContentType(nil)` 或改语义类型（`.oneTimeCode`）：前者已实测无效；后者把密码框谎报成一次性验证码字段，语义错误，且会引入空的自动填充弹层。
- 在密码框前放一个不可见的安全输入框吸收入口（纯公开 API）：要自己维护隐藏字段的焦点与制表顺序，还依赖「系统只给窗口里第一个安全输入框加入口」这条未文档化行为，比私有开关更脆。
- 自绘掩码输入框（普通 `NSTextField` 加自绘圆点）：零私有 API，但失去安全输入（键盘记录防护），光标、选区与输入法都要重做，代价大于收益。
- 维持现状：入口一直出现在新建服务器表单里（详情页只因字段只读或已预填，看起来没有该入口）。

## Consequences

- 这是本仓库第一处私有 API。Apple 换实现（方法消失）时探针静默回退到系统默认行为、不会崩溃；`PasswordAutofillOptOutTests` 会失败，提示重做这个缝。
- 关闭范围是字段级而非全局：同一表单的名称、服务器地址、端口等字段保持系统默认，新建表单与详情页表单共用这一份实现。
- 明文/密文切换会换掉承载的文本框，认领必须跟着新实例重做；该行为已由用例固定。
