# 第三方许可与归属资料

GameCase 的根许可证为 [GNU AGPL v3](LICENSE)。第三方材料保留各自适用的版权和许可，不因出现在本仓库就统一改为 AGPL。此索引记录已取得的许可文本及尚待溯源的部分；它不是二进制分发或素材授权已经完整合规的证明。

| 来源 / 材料 | 完整文本或现有通知 | 说明 |
| --- | --- | --- |
| LiveContainer / GameCase 派生代码 | [LICENSE](LICENSE)；[上游 README 归档](docs/livecontainer-readme.md) | 保留原作者及贡献者归属；本分叉的来源链见 README |
| NX2Apple 移植与改编代码 | [MIT](docs/licenses/NX2Apple-MIT.txt)、[原 NOTICE](docs/licenses/NX2Apple-NOTICE.txt) | 保留 seedds、jhaizhou、LNPANDY 与贡献者通知；需继续核对实际移植版本 |
| litehook | [MIT](docs/licenses/litehook-MIT.txt) | 固定版本的 Lars Fröder 版权通知 |
| OpenSSL 3.3.3 分发包 | [原分发 LICENSE](docs/licenses/OpenSSL-distribution-LICENSE.txt) | 当前 3.x 采用 Apache-2.0；文件中关于旧版双许可证的说明不代表本项目使用了旧版 OpenSSL |
| CydiaSubstrate / ElleKit 兼容框架 | [原 LICENSE](Resources/Frameworks/CydiaSubstrate.framework/LICENSE) | 原文本已随框架分发 |
| CFastFind / PatchfinderUtils | [MIT](docs/licenses/PatchfinderUtils-MIT.txt) | 另保留 LiveContainer/utils.m 中 Linus Henze 的原署名 |
| 原版 zsign | [上游 MIT](docs/licenses/zsign-upstream-MIT.txt) | 不能凭此认定所有 Feather/LiveContainer 修改都仅受 MIT 条件约束 |
| Feather 项目 | [GPLv3](docs/licenses/Feather-GPL-3.0.txt) | 上游 README 记录的签名代码来源之一；具体采用版本与文件范围待核实 |
| libarchive 头文件 | [archive.h](LiveContainerSwiftUI/Utilities/archive.h)、[archive_entry.h](LiveContainerSwiftUI/Utilities/archive_entry.h) | 原文件保留两条款 BSD 通知；iOS 系统动态库不是本仓库重新打包的库 |
| Apple 接口头文件 | [libproc.h](LiveContainer/Tweaks/libproc.h) | 原文件标注 APSL-2.0，适用范围与相关例外仍需专项核对 |

完整审查状态、二进制分发缺口和未核实图片素材见 [审查记录](docs/license-review.md)。
