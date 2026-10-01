# EmailX 原生 macOS 27 UI 改造与验收

本轮在已整合性能优化的 main（07b445ce）基础上，完成全应用界面代码审计和原生控件改造。原生化以 SwiftUI/AppKit 标准组件为依据：系统负责控件外观、边界、键盘焦点和工具栏溢出，不给邮件正文或每个内容块叠加玻璃。本文区分代码改造、运行验证与尚未执行的验收，不把编译成功当作全部场景通过。

## 全应用范围

| 区域 | 最终实现 |
| --- | --- |
| 主窗口、三栏布局 | NavigationSplitView、原生 Sidebar List、NSTableView、统一 NSToolbar；搜索使用 NSSearchToolbarItem。 |
| Sidebar、文件夹操作 | Label 与系统 badge；创建、重命名使用原生 alert/TextField。离线与错误信息位于内容顶部，使用 safeAreaInset，不遮挡邮件或占据 Sidebar 底部。 |
| 邮件列表、分页、批量操作 | 保留原生 NSTableView 和分页；语义字体、系统 SF Symbols；完整邮件摘要与已读、旗标、附件、会话数量提供辅助功能标签。分页、批量操作使用标准 bordered Button，批量动作可换行。 |
| 阅读区、收件人 | 语义标题与标准按钮/Menu；地址布局支持换行，头像只作装饰；加载与失败状态使用 ProgressView/ContentUnavailableView。 |
| 独立邮件窗口 | 真正的 NSToolbar，默认回复、归档、删除，允许定制与溢出；每个窗口操作自己的邮件。账户和旗标查询使用 GRDB 的 UUID 类型，兼容生产数据库的 BLOB 主键，独立于当前列表页。 |
| HTML、纯文本、EML | WKWebView 是系统邮件内容渲染组件，继续使用原有过滤、CSP、CID 和外部链接规则；邮件作者内容不强制改成应用主题。EML 使用原生文档窗口，源码使用语义等宽字体和标准 Copy/Close。 |
| 写信 | 每个草稿自己的 NSToolbar；收件人与主题使用 Grid/TextField/Picker；正文使用 NSTextView。格式动作在标准 accessory bar，窄宽度可横向滚动；链接使用 grouped Form sheet。 |
| 附件、拖放、预览 | 标准文件图标、语义字号、原生 bordered Button、NSOpenPanel 和 Quick Look；长文件名中间省略、保留完整提示。共享 FlowLayout 仅负责换行几何，宽度测量和放置一致。 |
| 设置导航、七个 pane | 后续严格复核已改为不可定制的 AppKit preference NSToolbar。内容仍使用 grouped Form、Picker、Toggle、Stepper、ColorPicker 和 HSplitView；详见后续验收报告。 |
| 添加账户 | 原生账户类型按钮；IMAP/SMTP 使用分组表单和带标签的字段；Gmail 使用标准授权入口。认证机制、凭证保存与网络安全规则未修改。 |
| 规则与签名 | 标准编辑字段、动态动作/条件；文件夹多选使用 popover/List/Toggle；移除账户、规则、签名有原生确认提示。 |
| 状态、认证、远程内容 | GroupBox、Label、标准 bordered Button/Menu；错误详情可选择和换行；VoiceOver 开启时不执行错误的自动消失计时。远程内容加载与永久信任仍是独立操作。 |
| 调试日志 | 原生 VSplitView 和 List，删除自绘拖动手柄；元信息与正文分行，删除固定列宽。过滤、复制、清空、自动滚动保留；邮件区保留最小可用高度，纵向日志分隔位置与原有横向三栏位置分别保存。 |
| 图标、系统菜单 | 保留上一阶段编译并选用的 EmailXAppIcon.icon 多层图标；菜单、About、系统文件对话框继续由 AppKit 提供。 |
| 空状态与辅助文件 | EmptyStateView 已是 ContentUnavailableView 的薄封装。FolderTreeBuilder/MessageListHelpers 是数据逻辑，QuickLookCoordinator 是系统桥接，均无需重画 UI。旧 SearchBarView 已不存在。 |

## 已执行验证

Release 构建成功，产物位于 `build/NativeUIDerivedData/Build/Products/Release/MyEmail.app`。签名完整性检查通过；它是本地构建，未表示已完成发行公证。

- `scripts/verify-native-ui.sh`：生产列表 cell 复用后辅助功能状态更新、长文本 FlowLayout 在浅色和深色环境中的有限宽度检查通过。
- `scripts/verify-compose-toolbar.sh`：原生安装、动作、菜单、状态更新、两个独立写信窗口、Cmd+Return 的可用/禁用状态与溢出项目检查通过。
- 现有邮件列表、后台调度和计数检查通过：完整会话、旧邮件可达性、分页与排序、元信息更新、60 秒 STATUS、5 分钟回退与重叠合并。服务层没有本轮修改。
- 隔离运行实例使用 `com.chengsen.EmailX.NativeUIProbe` 和独立容器，不替换安装版，也不修改真实账户配置。测试数据为 `.invalid` 域名的合成账户和邮件，没有发送邮件或连接真实邮件服务器。启动同步会尝试测试域名并产生预期的 DNS 失败，不作为真实收信验收。
- 窗口运行检查覆盖：欢迎/空状态、全部七个设置 pane、账户详情、IMAP 添加表单、Gmail 授权入口、签名编辑、规则编辑和文件夹多选、应用内浅色/深色选择后恢复跟随系统、调试日志、长标题邮件列表、HTML 阅读与远程内容阻止、独立阅读工具栏、回复草稿和链接插入表单。
- 独立阅读窗口的回复已生成正确收件人、主题和引用内容；系统菜单旗标操作将测试数据库 `is_flagged` 从 1 改为 0，已读操作将 `is_read` 从 1 改为 0，确认 UUID 查询修复实际生效。
- 最终构建重复打开、关闭调试面板后，邮件区分隔位置保持在 493pt，工具栏搜索与写信入口保留，修复了原先压缩至 100pt 的布局问题。

## 验收边界

代码已切换到原生控件体系，主要交互在隔离实例中通过。系统 Show Borders、完整 VoiceOver 操作、所有窗口尺寸及附件组合未逐项实机验收；原生控件承担系统适配，生产列表 cell 的辅助功能标签已有可运行检查，但这不等于所有辅助功能组合通过。截图采集分辨率不足以支持像素级视觉结论，本轮运行依据为实际控件树、操作结果与数据库状态。

真实公司账户认证、收信和 SMTP 投递没有在本轮重复测试；协议、安全过滤和调度代码保持原样，现有回归检查通过。原有 IMAP “Test Connection” 是日志占位，仍未实现真实连接探测；该功能缺口与 UI 原生化不同，不能将按钮展示视作连接测试通过。MCP HTTP 服务及令牌边界保持不变，没有新增 Codex 配置或扩大访问权限。

## 持续规则

新增界面优先使用标准系统组件、语义字体和带标签的控件。仅保留邮件内容渲染、文件图标、头像和换行布局等必要内容逻辑。以后改动共享布局或工具栏，运行相关 native UI/compose 检查；改动协议或调度时，再执行对应收信回归和真实账户验收。

依据：[Apple — Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)、[accessibilityShowBorders](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityshowborders)、[macOS 27 Release Notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes)。

## 后续严格复核

本报告为第一轮原生化记录。设置导航、快捷键、辅助功能树和长内容布局的后续修复，以及用户选择隔离模拟后的验收边界，见 [macOS 27 设计验收](macos27-design-acceptance-2026-10-02.md)。以该报告为最新状态，不能把本报告视作全部辅助技术场景通过。
