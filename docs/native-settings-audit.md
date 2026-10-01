# Settings 原生界面审计

审计日期：2026-10-02。范围为 `MyEmail/Views/Settings` 全部页面及其宿主 `SettingsWindowController`。本次保留账户认证、特殊文件夹、规则、签名、隐私、缓存、语言和 MCP 服务能力；不改变同步周期或收信调度。

## 逐页结果

| 页面或控件 | 原生组件与调整 | 保留的行为 |
| --- | --- | --- |
| Settings 窗口及分类 | 使用 AppKit `.preference` 样式的不可定制、始终可见 `NSToolbar` 切换七个 pane；原 Sidebar 导航删除。原生选中状态、当前 pane 标题、最小化及最大化按钮禁用、自动键盘导航。 | 七个分类、窗口位置及最近 pane 恢复。按需创建并保留已访问 pane 的 HostingView，切换不重建未保存编辑。 |
| General | 已使用分组 `Form`、`Picker`、`Toggle`，无需重新实现。 | 语言仅跟随 macOS、简体中文、English；写入 app-scoped `AppleLanguages`，下次启动生效。 |
| Accounts 列表与编辑 | 自绘固定分隔改成系统 `HSplitView`，列表宽度可调整；去掉强制行高。未选中时使用 `ContentUnavailableView`。标准表单和保存按钮。 | 账户重排、身份和文件夹设置；删除仍由 Repository 清理本地记录、Keychain 和本地附件，不删除服务器邮件。删除前增加系统确认。 |
| Provider chooser | 保留系统 bordered `Button`，没有自绘卡片边框或玻璃层。 | Gmail 和通用 IMAP 两条添加路径、取消操作。 |
| Generic IMAP | 移除表单内重复 Grid 标签布局，改为有语义标签的标准 `TextField`、`SecureField`、`Picker`；端口和安全类型不再靠固定宽度或空标签定位。 | 密码输入隐藏、默认端口切换、用户自定义端口保留、账户校验及添加后同步。错误文字不再限制为两行。 |
| Gmail | 按钮回到标准 bordered / borderedProminent 样式，保留 OAuth 等待、错误及完成状态。 | 实际认证异步路径、密钥管理及添加后同步；工作期间禁用重复操作。 |
| Signatures | 系统 `HSplitView`、列表、分组 `Form`、`TextEditor`；编辑器有正文辅助功能标签；未选择时使用系统占位。 | 签名账户、默认标记、自动保存、增加和删除；删除增加系统确认。 |
| Rules | 系统 `HSplitView`、列表、分组 `Form`；条件和操作字段取消固定宽度，使用有标签的原生控件纵向布局。减号按钮使用标准 bordered `Label`。 | AND / OR、收信触发、手动触发、文件夹范围、正则改标题、文件夹操作、应用和保存；删除增加系统确认。 |
| Folder scope popover | 原生 bordered 入口、系统 Popover、`List` 和 checkbox `Toggle`；保留层级缩进，显示角色文件夹本地化名称，入口具有辅助功能名称和值。 | 逐项及全选，空范围仍表示全部收件箱；不改变持久化的真实文件夹路径。 |
| Privacy | 可信发送人由 Form 原生行承载，移除表单里的独立滚动 List；添加、移除均使用标准按钮，图标按钮保留可朗读名称。 | 远程内容阻止、Gravatar 提醒和可信发送人列表。 |
| Appearance | 保留标准 Picker、Toggle、Stepper、ColorPicker；外观枚举使用本地化标题。引用颜色预览不再添加自绘灰色圆角外壳。 | 系统 / 浅色 / 深色外观，密度、日期、正文大小、引用颜色、Mail User Agent 显示。颜色预览里的细线是邮件引用内容示意，非交互控件。 |
| Advanced | 保留分组 Form；数据库大小改 `LabeledContent`，避免手动左右布局。 | 超时、正文预下载、缓存和调试入口。 |
| MCP | 保留分组 Form 中的 Toggle、状态行、端口字段和系统按钮；端口字段从固定宽度改为可适应范围。 | 默认关闭、仅本机监听、token、复制命令、重新生成 token、发送前确认和安全说明。 |

各设置内容区不再强制使用 `.glass` / `.glassProminent`。标准控件由 macOS 管理外观、Show Borders 和键盘焦点；没有为每个原生按钮重复绘制边框。需要的小间距、图标对齐和内容示意线条仍保留，它们不是自绘交互控件。

## 检查与验收边界

所有 Settings Swift 文件已通过 `xcrun swiftc -frontend -parse MyEmail/Views/Settings/*.swift`，`git diff --check` 通过。该检查仅证明语法和补丁格式；统一 Release 构建及运行验收由整合流程执行。

运行验收应覆盖七个设置分类、三个列表分隔的调整、长中文字段名、账户添加两个分支、规则条件/动作、文件夹 Popover、签名正文、语言保存，以及删除确认的取消路径。不同外观、Show Borders、增强对比度和 VoiceOver 需在实际系统中检查；静态使用原生组件不等于这些场景已全部通过。

原有 `Test Connection` 按钮仍仅记录日志，不执行真实 IMAP 探测。本次没有把它当作账户连通性通过证据，也没有修改认证协议。MCP 原有复制命令使用 `claude mcp add`；HTTP MCP endpoint 和 token 逻辑保持不变，不把该命令当作 Codex 客户端接入验收。

## 严格 Settings HIG 复核

原生组件本身不足以证明导航方式符合指南。2026-10-02 进一步核对 [Apple Settings HIG](https://developer.apple.com/design/human-interface-guidelines/settings) 的 macOS 平台条款后，确认旧 Sidebar 导航不符合其设置窗口工具栏建议；本轮改为真正的 AppKit 偏好设置工具栏。采用 SDK 提供的 `.preference` 样式，七个标准图标及标签 item 使用系统选中状态。工具栏不可定制、不从保存的配置恢复其他排列，隐藏工具栏动作无效，所有 pane 都有高可见优先级。窗口最小宽度 760 pt，留出七个分类及 master/detail 表单空间；表单保留原生滚动和内部可调整分隔。

`scripts/verify-settings-toolbar.sh` 编译真实的 SettingsWindowController 和 SettingsCategory / SettingsPaneView，使用简单 SwiftUI pane 及空 AppEnvironment 替身运行 AppKit 检查。已经验证 preference 样式、七个 toolbar item、七类 action 路由、活动项和标题、工具栏隐藏保护、最小化及最大化按钮禁用、访问过的 pane view 复用，以及新 controller 恢复最近 pane。此 fixture 不包含真实账户或数据库，不证明各真实 pane 的未保存字段、所有语言标签宽度和 VoiceOver 操作已经运行通过；这些留给整合后的真实页面验收。

## 导航项完整性修复

实机辅助功能操作曾成功移除 Advanced，即使 `allowsUserCustomization` 为 false。该属性不能作为固定导航完整性的唯一保证。公开 mutation 拦截能阻止删除，但不能阻止 AX 内部重排，因此最终复用 AppKit 的 `NSToolbarDelegate` 标准入口：`toolbarImmovableItemIdentifiers` 返回全部七类，`toolbar(_:itemIdentifier:canBeInsertedAt:)` 拒绝用户移动 / 移除。SDK 对前者明确规定集合中的 item 不可拖动或移除。

整合实机已验证七个设置按钮不再暴露 AX 移动 / 移除动作，Option–Command–T 不会隐藏设置导航。随后删除了临时 NSToolbar mutation 锁子类，直接使用 NSToolbar，仅保留公开原生委托；该简化版本已再次 Release 构建并实机复验：七项均不再暴露移动／移除动作，工具栏显隐保护和最近 pane 恢复通过。probe 验证完整 immovable 集合及每类禁止用户移动 / 移除的委托返回值，不将程序直接调用 remove API 视为用户交互路径。
