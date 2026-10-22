# 代理规则来源研究（2026-09-24）

> 研究日期：2026-09-24。本文只记录在线核验到的源项目、原始数据、生成工具和分发物，不把任何列表描述为完整、实时准确或适合所有网络。访问状态以本次核验为准；上游可能在报告之后变化。

## 结论先行

推荐将规则链分成四层：

1. **代理域名原始源**：继续以 [gfwlist/gfwlist](https://github.com/gfwlist/gfwlist) 的官方 `gfwlist.txt` 为可选的 GFWList 输入；必须解码、解析和转换，不能把该 URL 当作 PAC JavaScript 直接提供给客户端。
2. **中国直连域名原始源**：优先使用 [v2fly/domain-list-community](https://github.com/v2fly/domain-list-community) 的 `cn` / `geolocation-cn` 数据；需要“更偏向大陆直连”的现成 `geosite.dat` 时再评估 [Loyalsoldier/domain-list-custom](https://github.com/Loyalsoldier/domain-list-custom)，但要锁定版本并记录它相对 v2fly 的删改。
3. **中国大陆 IPv4 CIDR 原始/准原始源**：默认首选 [gaoyifan/china-operator-ip](https://github.com/gaoyifan/china-operator-ip) 的 `ip-lists` 分支；若优先考虑新鲜度，可把 [misakaio/chnroutes2](https://github.com/misakaio/chnroutes2) 作为 BGP 聚合备选；若要求可审计的注册分配基线，则直接消费 [APNIC delegated statistics](https://ftp.apnic.net/stats/apnic/delegated-apnic-latest)，自行从地址起点和数量换算 CIDR。不要把 IP 地理归属当作域名可达性证明。
4. **转换与分发**：Clash/Surge/Quantumult/sing-box/V2Ray 的发布文件可使用 [Loyalsoldier/geoip](https://github.com/Loyalsoldier/geoip)、[Loyalsoldier/v2ray-rules-dat](https://github.com/Loyalsoldier/v2ray-rules-dat) 或 ACL4SSR 的相应产物，但它们是生成/分发层，不应替代上述源数据；NG2 应生成并缓存自己的本地 PAC 快照。

对本仓库 NG2 的实际建议是：保留 GFWList URL 作为“远程源配置”，但将未来实现限定为“下载快照 → 校验/解码 → 解析可表达的规则 → 生成本地 PAC”；中国直连域名和 CIDR 不应未经转换直接塞入现有 PAC 用户规则字段。当前 NG2 的 `PACUserRules` 只把 `@@` 规则转换为 DIRECT，普通代理规则会保持默认 SOCKS，且 PAC 生成器没有 CIDR 匹配能力；这与完整 GFWList/PAC 编译器不是同一件事。

## 评价标准与格式边界

- **原始规则源**：维护者直接编辑或由公开注册/BGP数据直接产生的输入，如 GFWList 的源列表、v2fly `data/*`、APNIC delegated 文件、gaoyifan 的 BGP 结果。
- **转换后的分发文件**：由源数据生成的 `geosite.dat`、`geoip.dat`、SRS/MRS、Clash/Surge 文本等；方便使用，但应保留上游版本、生成时间和校验值。
- **生成工具**：负责解码、合并、过滤、格式转换或压缩的代码；工具本身不是规则正确性的来源。
- **推荐组合**：为 NG2 选择的输入和转换路径，不等于把多个列表无条件并集。并集越大，CDN/云厂商共享地址导致的误直连越多。

PAC 只能自然表达域名/URL匹配和 `DIRECT`/代理返回值；CIDR 需要额外的 IP 解析逻辑，且 PAC 的 `dnsResolve()` 会引入 DNS、性能和失败语义，不建议把整套中国 IP 段硬编码进 PAC。Clash、Surge、Quantumult 和 sing-box/V2Ray 则分别有自己的 `DOMAIN-SUFFIX`/`IP-CIDR`、`RULE-SET`、SRS/MRS 或 `geosite`/`geoip` 语义，不能只改文件扩展名。

## 1. GFWList：需要代理的网站/域名

### 原始源与规范

- 源项目：[gfwlist/gfwlist](https://github.com/gfwlist/gfwlist)。官方 README 称其为官方 GFWList 仓库，并发布 GitHub raw、GitLab、Repo.or.cz 和 jsDelivr 地址；建议优先使用仓库源或官方 README 中的镜像入口。[README](https://github.com/gfwlist/gfwlist/blob/master/README-EN.md)
- 当前原始分发物：[gfwlist.txt](https://raw.githubusercontent.com/gfwlist/gfwlist/master/gfwlist.txt)。本次读取到的编码头包含 `AutoProxy 0.2.9`、`Expires: 6h`、`Last Modified: Mon, 21 Sep 2026 12:27:46 +0000`，并声明 LGPL-2.1 URL；该文件是 Base64 编码的 AutoProxy 规则，不是 PAC JavaScript。[原始文件](https://raw.githubusercontent.com/gfwlist/gfwlist/master/gfwlist.txt)
- 规范要点来自源文件头和维护工具关联：[gfwlist/apollyon](https://github.com/gfwlist/apollyon) 是 GFWList 官方 README 指向的维护脚本仓库，包含 checksum、规则检查和 CIDR 计算脚本。分发物解码后仍可能含 `@@` 例外、URL锚点、通配符和正则；转换器若只抽取域名会丢失语义。

### 维护活跃度与风险

- GitHub 组织页在本次访问时显示主仓库 past-year activity 有更新，搜索结果显示最近更新到 2026-08-09；原始文件头的 2026-09-21 修改时间说明源列表仍有较新的发布内容。[组织页](https://github.com/gfwlist)
- 官方 README 明确说新提交不会实时进入列表，通常要经过可用性测试；因此它不是实时封锁状态 API，也不应宣称覆盖所有被阻断网站。[README](https://github.com/gfwlist/gfwlist/blob/master/README-EN.md)
- 许可证/分发：源文件头指向 LGPL-2.1；分发时应保留许可证和上游归属。CDN/raw 镜像是传输层，不应被当作独立来源；锁定具体 commit 或保存 checksum，避免远程内容无提示漂移。
- 误匹配/漏匹配：共享 CDN、第三方登录、国际化域名、URL路径规则和正则都可能导致误代理或漏代理。GFWList 目标是“需代理的候选规则”，不是中国境内直连白名单。

### 适配矩阵

- **PAC**：适合，但必须 Base64 解码、按 AutoProxy 语义解析并编译为 `FindProxyForURL`；`@@` 例外必须优先于代理规则。GFWList 官方 issue #2637 记录了用户请求直接提供 PAC JavaScript，状态为 closed as not planned，说明官方 URL 本身不是 PAC 成品。[issue #2637](https://github.com/gfwlist/gfwlist/issues/2637)
- **Clash/Surge/Quantumult**：适合经过专用转换器生成目标规则；不要把原始 Base64 当作这些客户端的 `RULE-SET`。
- **sing-box/V2Ray/geosite**：不应直接当作 geosite 输入；应转为目标格式，或使用 v2fly/Loyalsoldier 的原生 geosite 体系。
- **NG2 local PAC**：适合作为一个代理规则输入，但应在本地快照编译；远程下载失败、解码失败、未知语法或校验失败时保留旧快照，不应生成“空规则即全部直连”的危险回退。

## 2. 中国常用网站直连域名

### v2fly/domain-list-community：首选原始域名体系

- 源：[v2fly/domain-list-community](https://github.com/v2fly/domain-list-community)。项目明确说明它维护供路由使用的 domain lists，不主张某个域名必须被阻断或代理；`cn`、`geolocation-cn`、`tld-cn` 等是可组合的分类，不是“所有中国网站”的保证。[README](https://github.com/v2fly/domain-list-community/blob/master/README.md)
- 访问/活跃度：本次访问看到 GitHub 页面显示约 5,819 commits、75 issues、59 PRs；V2Fly 组织页显示该仓库最近更新到 2026-09-22，属于持续维护的源项目。[仓库](https://github.com/v2fly/domain-list-community)、[组织页](https://github.com/v2fly)
- 格式：`data/*` 支持 `domain:`、`full:`、`keyword:`、`regexp:`、`include:` 和 `@attr`；裸域名按 domain/root-domain 语义处理。官方生成器代码负责解析并生成 `dlc.dat`，工作流还导出 plaintext YAML 和 checksum。[生成器](https://github.com/v2fly/domain-list-community/blob/master/main.go)、[构建工作流](https://github.com/v2fly/domain-list-community/blob/master/.github/workflows/build.yml)
- 分发：官方 release 提供 `dlc.dat`、plain YAML 和 SHA-256；V2Ray 文档定义 `geosite:cn` 为常见大陆网站域名与 `tld-cn` 的组合，并说明 `geolocation-cn` 是常见大陆网站域名。[官方路由文档](https://github.com/v2fly/v2fly-github-io/blob/master/docs/en_US/config/routing.md)
- 许可证：仓库显示 MIT；数据条目仍可能有各自的事实/来源和第三方内容问题，不能把 MIT 自动解释成所有域名数据都无条件免审。[LICENSE](https://github.com/v2fly/domain-list-community/blob/master/LICENSE)
- 风险：分类判断与“当前从某个网络访问一定直连”不同；多地部署、海外 CDN、同一公司不同地区服务会造成误直连或误代理。`regexp`/`keyword` 转 PAC 时尤其容易扩大匹配范围。
- 适配：原生适合 V2Ray/Xray/geosite；可由工具转换为 sing-box、Clash、Surge/Quantumult；生成 PAC 前应只允许 `domain`/`full` 等可审计子集，明确丢弃/报告 `regexp`、`keyword`、属性和 include 的转换损失。

### Loyalsoldier/domain-list-custom：偏大陆使用场景的转换版

- 源/产物：[Loyalsoldier/domain-list-custom](https://github.com/Loyalsoldier/domain-list-custom)。README 明确它基于 v2fly/domain-list-community，并把 `dlc.dat` 重命名为 `geosite.dat`；它移除 `cn`、`geolocation-cn`、`geolocation-!cn` 中部分 `@ads`、`@cn`、`@!cn` 属性规则，目的之一是避免国区 Steam 等有大陆接入点的服务被不必要地代理。[README](https://github.com/Loyalsoldier/domain-list-custom)
- 访问/活跃度：本次访问显示 62 commits、2 PR、0 issue；有持续产物发布，但项目规模和讨论面明显小于 v2fly。因此推荐它作为“有明确偏好后的分发版”，不作为唯一真相源。
- 格式/适配：直接面向 geosite.dat 兼容客户端；其 README 列出 Hysteria、Shadowsocks-windows、Xray-core、Trojan-Go、Leaf 等兼容范围，并有 latest release 下载地址。要生成 PAC/Clash/Surge/Quantumult，仍需从源文本或可导出的 plaintext 规则再转换。
- 许可证：仓库显示 MIT；但它是二次整理版，分发时仍需保留上游 v2fly 归属和版本链。误匹配/漏匹配风险来自主动删改属性和上游继承，必须记录基准 commit。
- 推荐理由：如果产品目标是“大陆常用服务尽量直连”，它比直接把全部 `geosite:cn` 解释成 PAC 更接近该意图。Caveat：不能把“去掉部分属性”理解为网络可达性验证，也不能与 GFWList 无条件并集。

### ACL4SSR：常用的聚合/转换分发层，不是唯一原始源

- 源：[ACL4SSR/ACL4SSR](https://github.com/ACL4SSR/ACL4SSR)。README 直接列出 `ChinaDomain.list`（国内常见域名、直连 CDN）、`ChinaCompanyIp.list`（BAT及云厂商 IP）、`ChinaIp.list`，以及 `fullgfwlist.acl`、`gfwlist-banAD.acl` 等成品；同时说明 Clash 目录是可配合 subconverter 使用的规则碎片。[README](https://github.com/ACL4SSR/ACL4SSR/blob/master/README.md)
- 访问/活跃度：本次访问显示约 6,441 commits、106 issues、24 PRs；搜索结果显示最近更新到 2026-07-31，仍在维护，但它把多种目的（去广告、GFW、国内直连、订阅转换）混在一个发行体系中。
- 格式：ACL、Clash rule fragments、subconverter 配置及 Surge/Quantumult/V2Ray 等目标模板；使用前必须确认目标客户端支持的字段和规则顺序。`ChinaCompanyIp.list` 这类云厂商 IP 规则尤其不能等同于“中国 IP 段”。
- 许可证/分发：README 标示 CC-BY-SA-4.0；若把规则或改编后的聚合物随应用分发，应保留署名、许可证和相同方式共享义务，且核对其嵌入来源的许可证。不能只复制 raw URL 而省略 notices。[README license section](https://github.com/ACL4SSR/ACL4SSR/blob/master/README.md)
- 风险：聚合规则的云厂商/共享 CDN 误直连概率较高；去广告条目可能误伤；各成品的生成链和上游版本不一定与当前 GFWList/v2fly 同步。
- 适配：Clash/Surge/Quantumult 最方便；可作为比较基线或人工挑选 `ChinaDomain`，不建议 NG2 直接依赖完整 ACL4SSR 成品，也不建议把它当成 PAC 的透明输入。

### felixonmars/dnsmasq-china-list：DNS 分流源，不是代理规则源

- 源：[felixonmars/dnsmasq-china-list](https://github.com/felixonmars/dnsmasq-china-list)。官方 README 的目标是改善中国域名的 DNS 解析速度/CDN选择，并明确提示这些配置“不稳定、风险自负”；仓库包含 `accelerated-domains.china.conf`、更新脚本和 dnsmasq/unbound/bind 生成路径。[README](https://github.com/felixonmars/dnsmasq-china-list)
- 本次原始文件访问到约 110,460 行；格式是 `server=/example/114.114.114.114`，表达“该域名向某 DNS 服务器查询”，不是 `DIRECT`/`PROXY` 决策。[accelerated-domains.china.conf](https://raw.githubusercontent.com/felixonmars/dnsmasq-china-list/master/accelerated-domains.china.conf)
- 访问/活跃度：GitHub 页面显示约 288,692 commits、31 issues、20 PRs；大量提交是自动生成/更新，维护活跃度高，但不代表每条域名都经过代理分流验证。
- 许可证：WTFPL v2；许可证文本允许极宽泛的复制修改，但产品分发仍应保留来源说明，并审查其中使用的上游数据。[LICENSE](https://github.com/felixonmars/dnsmasq-china-list/blob/master/LICENSE)
- 适配：适合 dnsmasq/Unbound/BIND 等 DNS 配置；不直接适合 PAC、Clash/Surge/Quantumult 或 geosite。转换成直连域名时会丢掉 DNS 服务器语义和更新意图。
- Caveat：它可作为中国域名候选集或 DNS 旁证，但不推荐作为 NG2 的代理直连主源；域名量大、可能含加速/广告/临时域名，误直连风险高。

## 3. 中国大陆 IPv4 CIDR

### gaoyifan/china-operator-ip：推荐的可消费 CIDR 分发源

- 源：[gaoyifan/china-operator-ip](https://github.com/gaoyifan/china-operator-ip)。项目说明以 BGP/ASN 数据生成中国运营商 IPv4/IPv6 库，CIDR 成品放在 `ip-lists` 分支，并由 GitHub Actions 每日更新；README 还明确提示覆盖率不可能等同商业库、部分骨干地址可能遗漏。[README](https://github.com/gaoyifan/china-operator-ip)
- 格式/适配：`china.txt`/`china6.txt` 及运营商拆分文件是一行一个 CIDR，适合转换为 Clash/Surge/Quantumult 的 IP-CIDR 或 sing-box rule-set；也适合生成 NG2 外部构建时使用的 IP 数据，但不适合直接放进 PAC。
- 活跃度：项目名和工作流承诺每日更新；本次页面显示 172 commits，持续有自动结果分支。其生成链依赖公开 BGP/RIB 工具，属于比手工维护更直接的动态来源。
- 许可证：MIT。[README/license](https://github.com/gaoyifan/china-operator-ip)
- 风险：BGP 宣告/ASN 归属是网络观察和运营商分类，不等于物理位置、当前网站服务位置或从用户所在地的直连可用性；共享云/Anycast/跨境宣告仍会误匹配，未宣告或新前缀会漏匹配。推荐保存每日 commit/hash，不直接追踪可变 raw 的“最新”。

### misakaio/chnroutes2：高刷新率的 BGP 聚合备选

- 源：[misakaio/chnroutes2](https://github.com/misakaio/chnroutes2)。README 说明它从多个 BGP feed 生成更及时的中国路由，并由 route collector 每小时更新；仓库直接发布 `chnroutes.txt` 和 `chnroutes.mmdb`。[README](https://github.com/misakaio/chnroutes2)
- 其公开列出的 feed provider 是 AS917、AS906、AS131477 和 AS138195。它是多视角 BGP 观测的聚合结果，不是 APNIC 的注册分配快照；“每小时更新”表示数据刷新频率，不自动等于更准确或更完整。
- 格式/适配：`chnroutes.txt` 可作为 CIDR 转换输入，`chnroutes.mmdb` 适合支持 MMDB 的客户端；生成 Clash/Surge/Quantumult/sing-box 规则前仍应固定抓取时间、hash 和解析结果。许可证为 CC-BY-SA-4.0，和 gaoyifan 的 MIT 许可不同，随应用分发时必须单独保留署名并审查相同方式共享义务。[LICENSE](https://github.com/misakaio/chnroutes2/blob/master/LICENSE)
- 风险：有限 feed、路由收集点和当前 BGP 宣告会造成漏报/误报；未宣告但已注册的中国地址不会因为该项目“更实时”而出现。因此建议把它作为“新鲜度优先”的第二候选，与 gaoyifan 结果和 APNIC 注册基线做差异审计，不把它单独宣称为全部中国 IP。

### APNIC delegated statistics：权威分配基线，但需要自己换算

- 官方规范：[APNIC RIR statistics exchange format](https://www.apnic.net/about-apnic/corporate-documents/documents/resource-guidelines/rir-statistics-exchange-format/)。规范说明各 RIR 每日生成公开快照，稳定入口为 `delegated-<registry>-latest`；APNIC 当前入口是 [`delegated-apnic-latest`](https://ftp.apnic.net/stats/apnic/delegated-apnic-latest)。
- 格式：记录为 `registry|cc|type|start|value|date|status`；IPv4 的 `value` 是地址数量，不保证天然是 CIDR，必须由起始地址和数量算法换算；规范还明确 `cc` 表示首次分配/分派给组织的国家代码，不是“当前实际使用地点”的权威声明。[格式说明](https://www.apnic.net/about-apnic/corporate-documents/documents/resource-guidelines/rir-statistics-exchange-format/)
- 访问/更新：规范要求每日生产，并支持 `.md5` 和可选签名；本次 web 读取确认稳定入口存在，但二进制内容未由浏览器工具展开，未在报告中假报某个当日 serial。
- 许可证/分发：规范页定义公开交换格式和验证方式，但没有在该页给出一个可直接套用的 SPDX 数据集许可证。若把派生 CIDR 随应用发布，应保留 APNIC 归属、抓取日期、serial/checksum，并另行核对 APNIC 数据使用条款。
- 适配：最适合构建“注册分配审计基线”，不适合直接作为“今日中国公网可路由 IP”名单。建议和 BGP 结果交叉比对：APNIC 负责可解释的分配来源，gaoyifan 负责较接近实际宣告的可消费结果。

### IPdeny：方便的聚合分发，不是首选源

- 分发入口：[IPdeny country blocks](https://ipdeny.com/ipblocks/)，中国聚合文件为 [`cn-aggregated.zone`](https://www.ipdeny.com/ipblocks/data/aggregated/cn-aggregated.zone)。本次读取到的是一行一个 IPv4 CIDR 的文本，约 5,511 行，直接适合 shell 防火墙或转换器。
- 活跃度/状态：文件可访问并有当前内容，但公开页面没有像 APNIC 那样的 RIR serial、分配状态、BGP 观测链或可审计生成提交；因此只能视为便利的二次聚合分发。
- 许可证/分发风险：本次核验未找到与该 zone 文件绑定的清晰开源许可证或完整生成 provenance；在应用内再分发前应取得/核实其使用条件。不要用它替代 APNIC 或 BGP 源。
- 误漏匹配：聚合会隐藏原始粒度，国家归属本身也不是服务位置；适合粗粒度 IP-CIDR 规则，不适合作为 PAC 依据。

### RIPE/其他 RIR：用于交叉校验，不是中国大陆主源

- RIR 规范定义的注册集合包含 `apnic`、`arin`、`ripencc` 等；RIPE 的稳定入口是 [`delegated-ripencc-latest`](https://ftp.ripe.net/ripe/stats/delegated-ripencc-latest)。它对 RIPE NCC 管理区域有用，但中国大陆主分配源仍应先看 APNIC；跨 RIR 转移时还要按规范处理移动记录和重叠。[APNIC 标准](https://www.apnic.net/about-apnic/corporate-documents/documents/resource-guidelines/rir-statistics-exchange-format/)
- IANA 的 [IPv4 Address Space Registry](https://www.iana.org/assignments/ipv4-address-space) 适合解释 `/8` 分配主体，不是可直接用于中国直连的精细 CIDR 清单。

## 4. Loyalsoldier/geoip 与其他转换分发物

- [Loyalsoldier/geoip](https://github.com/Loyalsoldier/geoip) 明确提供每周自动生成的 V2Ray `dat`、MaxMind `mmdb`、sing-box `SRS`、mihomo `MRS`、Clash、Surge、Nginx 等格式。其 README 说明默认以 MaxMind GeoLite2 Country CSV 为基础，并特别用 gaoyifan 的 `china.txt`/`china6.txt` 替换中国大陆 IPv4/IPv6 数据。[README](https://github.com/Loyalsoldier/geoip)
- 它是很好的“格式转换/发布层”：Clash 用 `clash/ipcidr/cn.txt`，Surge 用 `surge/cn.txt`，sing-box 用 `srs/cn.srs`，纯文本用 `text/cn.txt`。这些文件可直接给对应客户端使用，但应记录 release tag、sha256 和上游 MaxMind/gaoyifan 来源，不应称为 APNIC 原始数据。
- 维护信号：README 声明每周四生成；release 页面能看到带 checksum 的成品和 2026-07-30 的 release 记录，发布签名页同时提示签名密钥已过期，因此需要把 checksum/来源审计与签名信任分开。[releases](https://github.com/Loyalsoldier/geoip/releases)
- 许可证：仓库含 `LICENSE`，且产物混合了项目代码、MaxMind 数据和 gaoyifan 数据；分发前应分别遵守项目许可证、MaxMind/GeoLite 条款和嵌入源的归属要求，不能仅根据仓库页面的开源标签判断全部数据可自由再分发。[LICENSE](https://github.com/Loyalsoldier/geoip/blob/master/LICENSE)
- 推荐理由：需要 sing-box/Clash/Surge 成品时，它减少自建转换器维护成本；Caveat：它的“CN”是地理/数据集分类，不保证站点直连，更不能直接进入 PAC。

[Loyalsoldier/v2ray-rules-dat](https://github.com/Loyalsoldier/v2ray-rules-dat) 是另一层增强分发物，README/API 显示它面向 V2Ray、Xray、mihomo、Hysteria、Trojan-Go、Leaf 等，仓库许可证为 GPL-3.0，且工作流引用 `domain-list-custom` 的 `cn.txt` 等输入。[工作流](https://github.com/Loyalsoldier/v2ray-rules-dat/blob/master/.github/workflows/run.yml) 因此适合客户端生态分发，不适合作为 NG2 的原始证据或新的第三方数据源。

## 5. 推荐组合与 NG2 适配建议

### 推荐组合 A：NG2 local PAC 的最小可审计路径

1. 输入：GFWList 官方 raw 或用户配置的 HTTPS URL；保存响应 hash、解码后的源版本/`Last Modified`，并限制大小、超时和重定向。
2. 编译：只在本地把可表达的 GFWList 域名/URL规则编译为 PAC；保留 `@@` 优先级；对 regex、IP字面量、复杂路径规则逐项报告“未表达”而不是静默扩大或缩小。
3. 直连：仅加入明确审计过的少量本机/局域网/用户例外。若未来引入 v2fly `cn` 或 `geolocation-cn`，应先转为明确的 `domain:`/`full:` 条目并生成独立快照，不能把 geosite 文件内容当作现有 `PACUserRules` 的同义输入。
4. 服务：继续由 NG2 本地 PAC endpoint 提供生成文档，失败时保留上一个有效快照；不要让远程列表 URL成为系统代理 PAC URL。

理由：与当前 NG2 的“local PAC / global SOCKS”边界一致，避免把远程规则获取、PAC编译和系统代理写入混成一个不可审计动作。Caveat：只靠 GFWList 会漏掉未收录的阻断域名，也不会自动生成完整中国直连白名单。

### 推荐组合 B：Clash/Surge/Quantumult/sing-box/V2Ray 的外部规则链

- 域名：v2fly `domain-list-community` 作为源；需要偏大陆直连语义时锁定 Loyalsoldier `domain-list-custom` 的 tag/commit。
- IPv4：默认使用 gaoyifan `ip-lists/china.txt` 作为日更 BGP/CIDR 结果；若更看重刷新频率，评估 chnroutes2 的 `chnroutes.txt`，并与 gaoyifan 做差异检查；APNIC delegated 每日文件作为审计对照；Loyalsoldier/geoip 只作为目标格式发布物。
- 目标客户端：优先使用对应生态的原生格式（geosite/geoip、SRS/MRS、Clash/Surge rule-set），不要把多套完整列表重复并入；使用明确的规则顺序，例如用户例外 → 私有地址 → 代理域名 → 中国域名/IP直连 → 默认策略。

理由：源、生成和分发责任清楚，更新频率与校验可记录。Caveat：同一域名可能同时具有中国和海外接入点；IP-CIDR 直连会把共享云地址上的非中国服务一起直连，需提供按业务的例外覆盖。

### 不推荐作为 NG2 主源的组合

- 完整 ACL4SSR 成品：功能丰富，但混合 GFW、去广告、国内域名、云厂商 IP 和转换模板，许可证与上游链复杂，适合作为对照或人工挑选。
- dnsmasq-china-list 直接转代理：它表达 DNS 服务器选择，不表达代理策略。
- IPdeny 直接作为唯一中国 CIDR 源：方便但 provenance、RIR 状态和数据许可不如 APNIC/BGP 源可审计。
- 把 `geosite:cn` 或 `GEOIP,CN` 直接声称为“全部中国网站/全部中国 IP”：这些是分类和路由数据，不是完整性或实时性承诺。

## 6. 交付时应记录的最小元数据

对任何进入产品构建的规则快照，至少保存：上游 URL、仓库和分支/commit 或 release tag、抓取时间（UTC）、HTTP `ETag`/`Last-Modified`（若有）、SHA-256、解码/转换工具版本、被丢弃的规则类型和许可证/归属文件。报告和产品文案都应使用“候选规则”“截至某次快照”，不要宣称列表完整或实时准确。
