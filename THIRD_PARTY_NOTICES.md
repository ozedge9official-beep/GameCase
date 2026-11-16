# 第三方许可与归属资料

GameCase / LiveContainer 的主许可证为 [GNU AGPL v3](LICENSE)。本分叉由 whodaregg 维护，修改日期和内容见 [版本记录](docs/releases/)。第三方材料保留各自适用的版权与许可；未把全部文件重新许可。

| 来源 / 材料 | 完整文本或现有通知 | 说明 |
| --- | --- | --- |
| LiveContainer / GameCase 派生代码 | [LICENSE](LICENSE)；[上游 README 归档](docs/livecontainer-readme.md) | 原作者 Duy Tran、主要维护者 hugeBlack 及原贡献者；直接父仓库 Joshliew33/GameCase，原 GameCase 来源 Tiaoge-tou/GameCase |
| NX2Apple 移植与改编代码 | [MIT](docs/licenses/NX2Apple-MIT.txt)、[NOTICE](docs/licenses/NX2Apple-NOTICE.txt) | 保留 seedds、jhaizhou、LNPANDY 和贡献者通知；其来源链包括 nxnative / d2r-mobile |
| litehook | [MIT](docs/licenses/litehook-MIT.txt) | 固定 a7e9f599d7f0b3d77008ad62bf10cb10dab6eca9，Copyright 2022–2024 Lars Fröder |
| litehook 外部 dyld ABI 头文件 | [APSL-2.0](docs/licenses/Apple-APSL-2.0.txt)、[dyld_cache_format.h 原文](docs/licenses/litehook-dyld_cache_format.h.txt)、[fixup-chains.h 原文](docs/licenses/litehook-fixup-chains.h.txt) | Apple Copyright 2006–2015 / 2018；这是 MIT 子模块中另有版权头的接口文件，不将其统称为 MIT |
| OpenSSL 3.3.3 | [3.3.3 原始 Apache-2.0](docs/licenses/OpenSSL-3.3.3-Apache-2.0.txt)、[包装分发 LICENSE](docs/licenses/OpenSSL-distribution-LICENSE.txt) | 包装固定 623c84da314e85363236507ca38a4bde65df21c3；旧版双许可证说明不代表本项目使用旧版 OpenSSL |
| CydiaSubstrate / ElleKit 兼容框架 | [原 BSD LICENSE](Resources/Frameworks/CydiaSubstrate.framework/LICENSE) | Copyright 2022 Évelyne Bélanger；继承的预编译二进制来源与溯源边界见构建说明 |
| CFastFind / PatchfinderUtils | [MIT](docs/licenses/PatchfinderUtils-MIT.txt)；LiveContainer/utils.m 的原署名 | 保留 Linus Henze 2021 与 Pinauten GmbH 通知 |
| ZSign 与 Feather 的独立 Zsign 子模块 | [原版 MIT](docs/licenses/zsign-upstream-MIT.txt)、[子模块固定版本 MIT](docs/licenses/zsign-package-MIT.txt) | zhlynn/zsign；Feather 通过独立 MIT 子模块使用的版本固定 c4ba9da4283031c07efa03bce42c4b8602d22e73，详见审查记录；保留 khcrysalis/Feather 修改版的上游归属及 LiveContainer 的修改 |
| libarchive 头文件 | archive.h、archive_entry.h 原版权头，亦随 IPA 单独附上 | Tim Kientzle、Martin Matuska 的两条款 BSD 通知；链接的是 iOS 系统动态库 |

1.0.20 起，以上全文与版权通知在 IPA 的 GameCaseLegal/ 中提供，可从设置中的“许可证与源代码”离线阅读。Release 同时提供主许可证、本索引、对应源码与构建资料。源码包包含本索引所指的文件；原文件头部声明继续保留。

本项目不因提供代码许可而授予游戏、美术、商标、证书或密钥的使用权；不暗示第三方作者为本分叉背书。当前处理结果、证据和仍有限制的历史依赖见 [审查记录](docs/license-review.md) 与 [构建说明](docs/BUILDING.md)。
