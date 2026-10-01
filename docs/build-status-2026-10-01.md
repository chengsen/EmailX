# EmailX 本机构建状态

2026-10-01，基于 `chore/emailx-baseline` 分支完成编译修复。主程序及 MUAResolver 的 Debug、Release 最低系统版本均为 macOS 27.0.1，README 要求 Xcode 27。

环境为 Xcode 27.0（27A266a）、macOS SDK 27.0、本机 macOS 27.0.1，构建 arm64 Release，使用本地 ad hoc 签名。

## 修复内容

原代码调用定制 SwiftMail 接口，项目依赖却指向官方 main，导致增量同步、分块取信和原始字节保存相关编译错误。已将已解析的官方版本固定到 `Vendor/SwiftMail`，保留上游许可证，并在本地集成中补齐 CHANGEDSINCE/MODSEQ、QRESYNC 结果、256 KiB 分块取信、最多 8 个请求一批的原始邮件流水线取信、文件夹操作和保留原始字节的 APPEND。复用上游命令编码、响应解析、连接管理及校验代码。

QRESYNC 协商或选择失败后禁止进入需要删除记录的 QRESYNC 路径，保留应用现有回退同步路径。分块取信按服务器 RFC822.SIZE 限制范围，并拒绝不完整响应。适配了 NIO 的强类型 MODSEQ 数值转换。

已补齐被 Git 忽略的 `MyEmail/App/Secrets.swift`，使用仓库模板，未填入真实 OAuth 凭据；Gmail OAuth 尚不可用。应用依赖锁文件纳入版本控制范围，防止重新克隆后无意解析到不同版本。

## 验证结果

- 最终 Release 构建返回 0，日志确认 BUILD SUCCEEDED：`build/build-fixed.log`。
- `codesign --verify --deep --strict` 通过。
- 应用和辅助 XPC 的 Info.plist 均确认最低系统版本为 27.0.1。
- 46 项测试、5 个测试组通过，覆盖增量 FETCH 编码、MODSEQ 响应解析、QRESYNC 删除记录与顺序处理、缺失 ENVELOPE 时的邮件头解析、部分 BODY.PEEK 响应校验及非 UTF-8 APPEND 数据保留。日志为 `build/package-tests.log`。
- `git diff --check` 通过。

产物：`build/DerivedData/Build/Products/Release/MyEmail.app`。逻辑文件总大小 37,389,507 字节；此值不是安装包大小或运行内存。

程序曾通过界面工具启动，进程可见；屏幕采集工具报错，未验收窗口及交互。最后一轮修复后的真实账户同步、附件下载和邮件发送均未验收。未安装到 Applications，未导入或迁移雷鸟账户及邮件。公司 EAS 接入不属于此次构建修复，当前仍以项目原有 IMAP/SMTP 接入为基础。

## 重现命令

```sh
xcodebuild -project MyEmail.xcodeproj -scheme MyEmail -configuration Release \
  -derivedDataPath build/DerivedData -destination 'platform=macOS,arch=arm64' \
  MACOSX_DEPLOYMENT_TARGET=27.0.1 CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build

swift test --package-path Vendor/SwiftMail --scratch-path build/PackageTests \
  --filter 'EmailXCompatibilityTests|PartialFetchValidationTests|ResyncSelectMailboxCommandTests|FetchMessageInfoHandlerTests|FetchMessageInfoHeaderFallbackTests'
```
