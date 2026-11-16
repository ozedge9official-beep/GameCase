# 构建、安装与源码包

本分叉由 whodaregg 维护，基于 Joshliew33/GameCase、Tiaoge-tou/GameCase 和 LiveContainer；原作者及第三方归属见 README 与 THIRD_PARTY_NOTICES.md。主许可证仍为 GNU AGPL v3。修改日期和内容见 docs/releases/。

## 获取对应版本

从同一 Release 下载 GameCase.ipa、GameCase-source.tar.gz、LICENSE、THIRD_PARTY_NOTICES.md 与 SHA256SUMS。源码包附 SOURCE-MANIFEST.json，记录版本、构建源码 commit/tree、固定子模块和 OpenSSL 原始源码 SHA-256。PR 构建也把 IPA 与源码包放在同一 Actions 附件中；正式发布时校验二者的源码 tree，允许 squash 合并导致 commit 不同但 tree 完全相同。

源码包已展开 litehook 和 OpenSSL 所需的固定材料，包含 iOS arm64 的预编译 OpenSSL slice、原构建脚本及 OpenSSL 3.3.3 官方源码压缩包。其他平台的预编译 slice 未包含；本项目发布命令仅构建 iOS arm64。GitHub 自动生成的 Source code ZIP 不展开子模块，请优先使用上述单独的源码包。

也可获取 Git tag（以 1.0.21 为例）：

```sh
git clone --recurse-submodules --branch v1.0.21 https://github.com/whodaregg/GameCase.git
cd GameCase
```

## 构建 GameCase

需要 macOS、Xcode 26.2（含 iPhoneOS SDK）、Python 3 与系统命令行工具。对应 CI 见 .github/workflows/build.yml。解压源码包后进入 GameCase-source；从 Git 获取时进入 GameCase。

```sh
python3 -m unittest discover -s tests -v
python3 tests/run_swift_regressions.py
python3 tests/run_cheat_regressions.py
cc -Wall -Wextra -Werror tests/current_process_files.c -o /tmp/gamecase-file-tests
/tmp/gamecase-file-tests
xcodebuild archive -archivePath archive -scheme LiveContainer -project LiveContainer.xcodeproj -sdk iphoneos -arch arm64 -configuration Release
archive_path=archive sh .github/build_github.sh
```

项目使用随源码提供的签名工具生成供侧载的 IPA；本仓库不提供个人开发者证书、私钥或 Apple 账号。安装前按 README 的证书要求，用你有权使用的开发者身份重新签名，签名工具应保留 GameCaseLegal 资料目录。重新编译或修改应用不需要原维护者的私有签名密钥；实际安装和运行仍受设备与 Apple 平台规则约束。上述命令不是跨 Xcode 版本逐字节一致的构建保证。

## OpenSSL 的来源与重建

使用的包装提交为 623c84da314e85363236507ca38a4bde65df21c3（krzyzanowskim/OpenSSL）。其版本为 3.3.3，官方源码压缩包 SHA-256：

```
712590fd20aaa60ec75d778fe5b810d6b829ca7fb1e530577917a131f9105539
```

源码包将原始 openssl-3.3.3.tar.gz 放在 OpenSSL/，保留该固定版本的 Makefile、Project.swift、config、patches、scripts、shim 和 support。原脚本会应用存在的版本补丁，并调整头文件供 framework 使用。重建包装框架需额外安装该版本构建文件使用的 Tuist 4（该提交 .tool-versions 指定的主版本）：在 OpenSSL 目录按其 README/Makefile 的 `make project`、`make build`、`make frameworks SIGNING_IDENTITY=-` 执行；原脚本构建多个 Apple 平台，因此需要安装相应 SDK。生成后使用新的 Frameworks/OpenSSL.xcframework 构建 GameCase。原包装构建脚本和配置是依赖重建的依据，不能只以 OpenSSL 版本字符串证明预编译二进制逐字节可复现。

## 其他依赖与分发范围

- litehook 固定 a7e9f599d7f0b3d77008ad62bf10cb10dab6eca9，源码、版权和 MIT 文本随包保留；其 external/include 的两个 Apple ABI 头文件另保留 APSL-2.0、原版权和完整原文，不能用子模块 MIT 概括全部文件。
- ZSign 源码和本项目修改直接位于 ZSign/；Feather 的独立 Zsign 子模块已核对到 MIT，证据与范围见 docs/license-review.md。未把 Feather 主项目的 GPL 自动套用到它的独立 MIT 子模块。
- Resources/Frameworks/CydiaSubstrate.framework 是继承自 LiveContainer 的 ElleKit 兼容框架，保留原 BSD 许可。它的二进制来自上游 LiveContainer 提交 abb583577a40af1a7455f0753a7bb2b14a809e18；本仓库文件 blob 为 8deb4185968db5df964ed76c113bf58c4b31eee9。公开 ElleKit 源码：https://github.com/tealbathingsuit/ellekit 。目前没有足以证明该历史二进制精确对应 ElleKit 哪个提交的记录，不虚构其可复现性或来源提交。
- libarchive 使用系统动态库；仓库携带的头文件版权通知保留并随 IPA 提供。
- iOS SDK、Xcode 和系统库由平台提供，不放入本项目源码包；使用时遵守各自条件。

本次补齐可取得的源码、固定依赖、原始许可和构建资料，并加入发布校验；这不等同于对历史预编译依赖的完整溯源认证。历史 tag/IPA 未被本次改动替换，详见审查记录。
