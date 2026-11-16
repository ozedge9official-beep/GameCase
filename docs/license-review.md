# 许可证与分发资料审查

核对日期：2026-11-17。核对对象：本仓库 `9561f7b591cf692c8ff20568340abb52c68035c2` 与已发布的 1.0.19 IPA。

这是基于可取得文件的技术审查记录，不是“全部合规”的认证。许可证适用范围、移植代码的完整来源链及图片授权仍需核实；涉及争议时应由具备相应资质的专业人士评估。

## 已确认

| 对象 | 查到的依据 | 应保留或补充的资料 |
| --- | --- | --- |
| GameCase / LiveContainer | 根目录 LICENSE 为 GNU AGPL v3；与 LiveContainer 及直接父仓库 Joshliew33/GameCase 的许可文本一致 | 原有声明、完整 AGPL、修改说明和日期、对应源码及构建/安装说明 |
| 原项目来源 | GitHub fork 元数据记录直接父仓库 Joshliew33/GameCase，source 为 Tiaoge-tou/GameCase | 两级来源均保留，避免把本分叉写成从零创作；本次 Tiaoge-tou/GameCase 直接访问返回 404，不能据此删除其归属 |
| NX2Apple | 当前公开 LICENSE 为 MIT，列有 seedds、jhaizhou、LNPANDY and NX2Apple contributors；NOTICE 说明 nxnative / d2r-mobile 的来源链 | 复制了代码的部分应保留相应完整版权与许可通知；致谢链接不能代替这些文本。当前版本的许可不能替代对实际移植版本的核对 |
| litehook | 固定子模块 a7e9f599d7f0b3d77008ad62bf10cb10dab6eca9 的 MIT，Copyright 2022–2024 Lars Fröder | MIT 完整文本与版权通知 |
| OpenSSL | 固定包装仓库 623c84da314e85363236507ca38a4bde65df21c3；iOS 头文件标明 OpenSSL 3.3.3、Apache-2.0 | 实际版本对应的许可、适用 NOTICE（如有）、版权通知及可验证的依赖构建来源，不能误套旧版 OpenSSL/SSLeay 的许可条件 |
| CydiaSubstrate 兼容框架 | 仓库及 IPA 内均有 Évelyne Bélanger / ElleKit 的三条款 BSD 风格 LICENSE | 保留现有文本；不得暗示 ElleKit 作者为本项目背书 |
| CFastFind 派生辅助代码 | LiveContainer/utils.m 保留 Linus Henze 2021 的署名及来源链接；PatchfinderUtils 当前公开 MIT 包含 Pinauten GmbH 的版权通知 | 保留已有署名并补许可文本，继续核对采用版本 |
| libarchive 头文件 | archive.h 与 archive_entry.h 自带两条款 BSD 文本及原版权声明 | 保留头部通知，并在分发资料中集中列明；iOS 系统 libarchive 动态库与本仓库携带的头文件应区分 |

完整已核对文本的副本见 [第三方通知索引](../THIRD_PARTY_NOTICES.md)。这些副本不会把其他文件自动重新许可。

## 需要优先补齐的分发资料

1. **IPA 内的许可资料。** 对 1.0.19 ZIP 路径检查时，仅发现 CydiaSubstrate.framework/LICENSE，未发现主 AGPL 或其他已确认依赖的集中许可资料。下一次实际二进制发布应随包加入主许可证与适用的第三方通知，并在设置页提供离线查看入口。本次文档补充不会改变已发布 IPA 的内容。
2. **每个安装包旁的明确源码入口。** AGPL 第 6(d) 条允许网络分发时从同一位置提供等效源码访问，也允许有清楚指引的另一源码服务器。不能只给“最新版 main”链接；应标明对应 tag/commit、子模块版本及构建说明，并持续保证访问。
3. **完整对应源码。** GitHub 自动生成的 Source code ZIP 不会自动展开子模块。`git clone --recurse-submodules` 是获取本仓库固定依赖的入口，但不是对“完整对应源码”义务的自动证明。尤其需要核对预编译 OpenSSL 的实际源码、配置及重建脚本是否齐备；分发者应保留必要源码与脚本，不能只依赖临时 Actions 产物。
4. **明显的修改说明及相关日期。** AGPL 第 5(a) 条要求修改版携带明显的修改通知和相关日期。保留原始声明，补充本分叉维护者、版本日期、实际变更与验证范围；不能声称是原作者官方发行。
5. **保留许可证及接收者权利。** 根许可证保持不变，适用的第三方许可分别保留。不要擅自把全部代码改为 MIT，也不要加入与已有许可冲突的“禁止修改/禁止再分发/禁止商用”等附加限制。免责声明不能替代履行许可条件。

## 尚不能由现有证据消除的风险

### 签名代码的来源与许可范围

归档的上游 README 明确说明 ZSign 最初来自 zhlynn/zsign，并采用了 khcrysalis 的 Feather 修改版。原 zhlynn/zsign 当前 LICENSE 是 MIT；Feather 仓库已迁移到 [claration/feather](https://github.com/claration/feather)，当前项目 LICENSE 为 GPL-3.0。

因此，不能仅凭当前原版 zsign 的 MIT 文件，就认定仓库中的所有 ZSign 修改都只有 MIT 条件。应追溯实际导入提交、逐文件版权与许可，确认 GPL 与 AGPL 组合时对各部分的要求，并保留相应通知和源码。GPLv3 与 AGPLv3 的组合条款并不等于所有部分都被自动改成同一种许可证。提供两份上游文本是审查资料，不是对当前每个文件的适用性作最终判断。

### Apple 标记文件

`LiveContainer/Tweaks/libproc.h` 明确标注 Apple Public Source License 2.0，并保留 Apple 版权头。应继续确认这些内容作为系统接口声明/头文件时的适用范围及相关例外，必要时评估替换为可合法使用的 SDK 声明。不能把它的原版权头删除或直接改标为 AGPL，也不能只凭根 LICENSE 就认定其全部条件已经满足。

### 游戏美术与截图

仓库携带两张游戏封面 `LiveContainerSwiftUI/GameCovers/cover-010013C00E930000.jpg`、`cover-0100A00019DE0000.jpg`，以及含游戏画面的说明截图。本次未找到这些素材的独立授权、可再分发许可或完整来源记录。

游戏美术不会因为被放入 AGPL/MIT 仓库就自动获得开源许可。“版权归原厂”“仅供学习”“无隶属关系”等文字也不等于授权。建议优先取得并记录许可，或换成有明确授权的原创/占位素材。截图的适用例外与合理使用需要结合实际用途和管辖区判断。联网抓取的商店图片同样需要考虑其权利与服务条款。

本次不擅自宣称素材已获授权，也不将任何尚未核实的外部代码统一重新许可。

## 核验来源

- [本仓库 AGPL](../LICENSE)，第 4、5、6、10、13、15、16 条。
- [LiveContainer LICENSE](https://github.com/LiveContainer/LiveContainer/blob/main/LICENSE)，blob `0ad25db4bd1d86c452db3f9602ccdbe172438f52`。
- [NX2Apple LICENSE](https://github.com/LNPANDY/NX2Apple/blob/main/LICENSE)，blob `cdf95f0e907f5220033acc72175fdedde7de4b06`；[NOTICE](https://github.com/LNPANDY/NX2Apple/blob/main/NOTICE)，blob `f15e580cc63b5130a78928490940fd369e22a4af`。
- [固定 litehook 许可](https://github.com/LiveContainer/litehook/blob/a7e9f599d7f0b3d77008ad62bf10cb10dab6eca9/LICENSE)。
- [固定 OpenSSL 分发许可](https://github.com/krzyzanowskim/OpenSSL/blob/623c84da314e85363236507ca38a4bde65df21c3/LICENSE.txt) 及该提交的 `ios-arm64/OpenSSL.framework/Headers/opensslv.h`。
- [Feather GPL](https://github.com/claration/feather/blob/main/LICENSE)，blob `f288702d2fa16d3cdf0035b15a9fcbc552cd88e7`；[原版 zsign MIT](https://github.com/zhlynn/zsign/blob/master/LICENSE)，blob `e36bb6e598fc0bc087eef9c04cf622a99d888f0b`。
- [PatchfinderUtils MIT](https://github.com/pinauten/PatchfinderUtils/blob/master/LICENSE)，blob `fc7ce3fb5d250d2772a9477fe8aff46ac5df2011`。

未修改源文件版权头、根许可证、既有版本标签或历史作者记录。
