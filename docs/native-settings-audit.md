# Settings 原生界面审计

审计日期：2026-10-02。范围为 `MyEmail/Views/Settings` 全部页面及其宿主 `SettingsWindowController`。本次保留账户认证、特殊文件夹、规则、签名、隐私、缓存、语言和 MCP 服务能力；不改变同步周期或收信调度。

## 逐页结果

| 页面或控件 | 原生组件与调整 | 保留的行为 |
| --- | --- | --- |
| Settings 窗口及分类 | 保留 AppKit 标准可调整窗口、自动键盘导航和 SwiftUI `NavigationSplitView` / Sidebar `List`。分类无需另造玻璃外壳。 | 七个分类及窗口位置恢复。 |
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
