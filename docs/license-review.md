# 许可证与分发资料审查

核对与修改日期：2026-11-17。最初核对对象为 main 的 9561f7b591cf692c8ff20568340abb52c68035c2 与 1.0.19 IPA；本次处理版本为 1.0.20。以下区分证据、已处理内容和仍存在的边界，不是“全部合规”的法律认证。

## 确认的许可与已处理内容

- 根 LICENSE 继续保持 GNU AGPL v3 原文，与 LiveContainer 和直接父仓库一致。保留 Duy Tran、hugeBlack、其他贡献者及 GameCase 的来源链：Joshliew33/GameCase → Tiaoge-tou/GameCase。原来源仓库当前访问 404，未据此删除归属。
- 新增 [第三方通知索引](../THIRD_PARTY_NOTICES.md) 和完整许可副本，涵盖 NX2Apple MIT/NOTICE、固定 litehook MIT 与其外部 Apple ABI 头文件的 APSL-2.0、OpenSSL 3.3.3 Apache-2.0 和包装分发许可、ElleKit BSD、PatchfinderUtils MIT、原版与 Feather 独立子模块的 ZSign MIT、libarchive 两份原始头文件版权通知。保留现有文件头部版权，不用致谢链接代替全文。
- 1.0.19 IPA 仅查到兼容框架原 LICENSE，未发现集中许可资料。1.0.20 起，在 Xcode 签名之前将完整许可资料复制到 GameCaseLegal/，设置页支持离线阅读。后续签名工具应保留该目录。
- 同一 Release 提供 GameCase-source.tar.gz、LICENSE、THIRD_PARTY_NOTICES.md 和 SHA256SUMS。源码包展开固定 litehook/OpenSSL 材料，另附校验 SHA-256 的 OpenSSL 官方源码及原始配置/构建脚本。源码 tree、依赖 commit 和版本记录在 SOURCE-MANIFEST.json；发布流程核验源码包、IPA 许可清单和目标源码 tree 一致。
- [构建与安装说明](BUILDING.md) 记录工具、命令、依赖重建和签名要求；不把 GitHub 自动生成、不展开子模块的 ZIP 当作唯一源码入口。
- 本分叉维护者、修改日期、变更范围及测试边界在每次发布说明中列明。未改变接收者修改和再分发权利，未加入“禁止商用”等冲突限制，未将本分叉宣称为上游官方发行。

## 签名代码：已核实的范围与修正

上游 README 记录最初来自 zhlynn/zsign，并采用 khcrysalis 的 Feather 修改版。Feather 已迁至 [claration/feather](https://github.com/claration/feather)，主项目 LICENSE 为 GPL-3.0；但其 `Zsign` 实际为**独立子模块**，不是仅凭主仓库许可证就能判定的普通子目录。

进一步追溯到该子模块 [claration/zsign](https://github.com/claration/zsign) 的固定提交 `c4ba9da4283031c07efa03bce42c4b8602d22e73`，其 LICENSE 是 MIT（blob `e36bb6e598fc0bc087eef9c04cf622a99d888f0b`，Copyright 2026 zhlynn）。已将该提交的原始许可单独保留。此前仅根据 Feather 主项目 GPL 提出的签名模块风险，现按这一更直接的证据修正；不把 GPL 自动套到独立 MIT 子模块，也不借此重新许可来自其他来源的改动。

本仓库 ZSign/ 包含 LiveContainer 的修改，与子模块并非逐文件相同。继续保留原始署名和上游归属，本分叉修改受原项目适用条款约束；当前公开子模块的许可是核对依据，不应虚构它就是所有历史导入代码的精确提交。

## Apple 头文件的处理

原 `LiveContainer/Tweaks/libproc.h` 含 Apple APSL-2.0 版权头，另有复制的 vnode/stat ABI 结构；实际用途仅是查询当前进程打开的文件路径。

本次将这一用途改为 SDK `<fcntl.h>` 的 F_GETPATH，仅保留 libSystem 函数签名与当前进程描述符列表所需的最小接口定义，移除不再使用的两个复制头文件；没有剥除其版权后换名重发。后台锁处理继续使用原有流程，并增加真实 Darwin 文件描述符测试。SQLite 私有查询符号不可用时转入原有 fcntl 锁查询，避免空指针调用。

此变更只适用于新版本当前代码，不声称撤销历史文件的许可条件。

递归检查还发现 litehook 固定子模块中的 external/include/dyld_cache_format.h 和 fixup-chains.h 也保留 Apple APSL-2.0 头。这些是 dyld 二进制格式的接口/布局定义；本次保留其完整原文、版权和 APSL 全文，并在 IPA 中离线提供，源码包亦保留固定版本原文件。它们未被改标为 MIT；移除本仓库不必要的头文件不代表所有依赖中都不存在 Apple 许可。不同许可部分的组合适用范围不作无依据的法律结论。


## 游戏封面与截图

本次未查到两张内置游戏封面及三个 README 游戏截图的独立再分发授权，因此从当前树移除这些文件和引用。保留本项目原有图标、LiveContainer 图标及贡献者归属，不将开源许可解释为游戏美术许可。

游戏自带封面、自定义选图和图标兜底继续可用。商店取图改为设置页主动操作，说明会发送游戏 ID/名称及需要相应使用权；浏览游戏库和导入 IPA 不再自动抓取。这个交互变化不等于第三方商店已经授权取图或再分发。

## 仍需保留的边界

1. **历史版本。** 未重写 Git 历史，未替换旧 tag、旧 IPA 及其截图。1.0.20 的补充不会自动补齐旧包或赋予历史图片授权。保留旧版本分发时，仍应提供相应的许可/源码资料并单独处理其中素材。
2. **继承的预编译框架。** CydiaSubstrate.framework 实为 ElleKit 兼容库，原三条款 BSD 许可已保留；二进制可追至 LiveContainer 提交 abb583577a40af1a7455f0753a7bb2b14a809e18、blob 8deb4185968db5df964ed76c113bf58c4b31eee9。尚无记录证明它精确对应 ElleKit 哪个源码提交。公开 ElleKit 源码入口和现有证据见构建说明，不能将此描述为完全可复现或全部历史溯源已经完成。
3. **历史移植版本。** NX2Apple、PatchfinderUtils 和 ZSign 当前可取得的许可已保留，仍需区分当前上游许可与实际历史移植来源，不虚构缺失的导入提交。
4. **外部内容与平台。** 用户应有权使用其游戏、图片、证书及数据。许可证、免责声明和“仅学习”文字都不替代不存在的权利。具体争议需要结合适用法律与事实评估。

## 可验证来源

- [本仓库 AGPL](../LICENSE)；LiveContainer 与直接父仓库根许可 blob `0ad25db4bd1d86c452db3f9602ccdbe172438f52`。
- [NX2Apple LICENSE](https://github.com/LNPANDY/NX2Apple/blob/main/LICENSE)，blob `cdf95f0e907f5220033acc72175fdedde7de4b06`；[NOTICE](https://github.com/LNPANDY/NX2Apple/blob/main/NOTICE)，blob `f15e580cc63b5130a78928490940fd369e22a4af`。
- [litehook 固定许可](https://github.com/LiveContainer/litehook/blob/a7e9f599d7f0b3d77008ad62bf10cb10dab6eca9/LICENSE)。
- [OpenSSL 固定包装源码与许可](https://github.com/krzyzanowskim/OpenSSL/tree/623c84da314e85363236507ca38a4bde65df21c3)；OpenSSL 3.3.3 官方源码 SHA-256 见构建说明。
- [Feather 独立 Zsign 子模块 MIT](https://github.com/claration/zsign/blob/c4ba9da4283031c07efa03bce42c4b8602d22e73/LICENSE)；[原版 zsign MIT](https://github.com/zhlynn/zsign/blob/master/LICENSE)。
- [PatchfinderUtils MIT](https://github.com/pinauten/PatchfinderUtils/blob/master/LICENSE)，blob `fc7ce3fb5d250d2772a9477fe8aff46ac5df2011`。
