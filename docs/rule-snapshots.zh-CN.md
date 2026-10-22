# 内置规则快照

[English](rule-snapshots.md) | [返回工程首页](../ShadowsocksX-NG2/README.zh-CN.md)

除特别说明外，命令从 `ShadowsocksX-NG2/` 执行，文中工程路径也相对于该目录。

规则模式使用的内置快照是显式维护产物：

- **geolocation-cn**（issue #63）：人工复验上游后运行 `Scripts/update-geolocation-cn.sh`，从固定版 [Loyalsoldier/domain-list-custom](https://github.com/Loyalsoldier/domain-list-custom) `geosite.dat` 解析 typed 条目并生成 `Vendor/rules/geolocation-cn/snapshot.json`。
- **china-ipv4**（issue #64）：运行 `Scripts/update-china-ipv4.sh`，从固定版 [gaoyifan/china-operator-ip](https://github.com/gaoyifan/china-operator-ip) `china.txt` 规范化并去重 IPv4 CIDR，生成 `Vendor/rules/china-ipv4/snapshot.json`。
- **gfwlist**（issue #65）：运行 `Scripts/update-gfwlist.sh`，从固定版 [gfwlist/gfwlist](https://github.com/gfwlist/gfwlist) `gfwlist.txt` 解码官方 Base64 AutoProxy 列表并生成 `Vendor/rules/gfwlist/snapshot.json`。`||host` / `||host^` 转换为域名后缀匹配；`|scheme://host`（可含合法端口）在路径为空或仅为 `/`，无查询、fragment 或用户信息，且 host 为无通配符的合法域名时，提取 host 转换为精确域名匹配，忽略协议和端口。仅含根路径 `/` 可转换，包含具体路径的规则继续跳过。`@@` 保留直连动作。其他 URL 前缀、路径、通配符、正则、单标签前缀与 IP 字面量规则逐类计入损失报告。被代理规则完全覆盖的 `@@` 例外不写入无效 ACL 项（sslocal 域名匹配 proxy_list 优先于 bypass_list），保留代理规则，遮蔽数只计入 `absorbedCount`；逐条取证输出到维护脚本 stdout。

快照使用 schema 2 / converter 2.0.0 的紧凑 JSON：每条规则只有 `action` 和 `match`，来源只在 `metadata.source`，转换报告只保留计数。被吸收的 `.cn` 条目与被遮蔽的 GFWList 例外不随快照分发，禁用宽规则后不再恢复；详见 [ADR-0024](adr/0024-snapshot-drops-absorbed-and-forensics.md)。旧版本快照拒载。

规则领域值与文件 DTO 独立演化。`ProxyRule` 同时表达规范化规则值与跨来源规则身份，自定义条目另外保留 UUID。自定义规则文件写入 schema 3，不再逐条保存 `source`；兼容读取 schema 1/2，读取不重写，下一次正常保存才更新格式。内置快照格式不变。见 [ADR-0039](adr/0039-rule-values-and-independent-storage-models.md)。

Python 是唯一的上游转换实现；Swift 只加载、校验并消费快照，不另行解析上游输入。转换脚本的离线回归检查：`PYTHONDONTWRITEBYTECODE=1 python3 Scripts/test-rule-snapshot-converters.py`。默认 `task test` 也会运行两组 Python 检查；可单独运行 `task test:rules`。另运行 `PYTHONDONTWRITEBYTECODE=1 python3 Scripts/test-rule-conversion-behavior.py`，验证转换行为和单测 bundle 使用的固定快照夹具。审查转换变化后，可通过同一命令加 `--write-fixtures` 重建夹具。夹具时间固定，正常测试逐字节检查生成结果。快照完整性检查：`Scripts/verify-rule-snapshots.sh`。

更新失败保留上一份有效快照。geolocation-cn 转换会因未知语法/损坏输入失败；china-ipv4 转换还会因异常格式（拒绝率过高）、全部失效或相对上一份快照的异常规模变化失败；gfwlist 转换因未知语法、损坏 Base64、异常规模或相对上一份快照的异常规模变化失败。普通构建由 `Scripts/verify-rule-snapshots.sh` 离线校验快照存在、摘要匹配且 schema/转换器版本一致，缺失或损坏即构建失败。分发物必须携带各自的 `NOTICE`（许可证与归属）。

规则模式「未匹配时代理」生成的 `proxy_all` ACL 同时包含中国域名与中国 IPv4 CIDR 直连候选，固定本地绕过优先。规则模式「未匹配时直连」生成的 `bypass_all` ACL 只编入 GFWList 可生效代理候选；两种默认动作不把全部内置来源无条件并集。未匹配目标与无可用规则命中的 IP 字面目标直连。**CIDR 判定可能触发本地 DNS 查询**：sslocal 为未命中域名做 IP 匹配时可能发起本地 DNS 查询，产品不承诺 DNS 查询均经远端 Shadowsocks 服务器。
