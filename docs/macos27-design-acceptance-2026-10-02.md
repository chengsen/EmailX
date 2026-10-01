# EmailX macOS 27 原生设计复核与模拟验收

后续 UI 与交互补充验收见 [最新报告](ui-interaction-acceptance-2026-10-02.md)，包含链接撤销、收件人键盘操作及完整最小窗口布局修复。以下保留本轮历史证据。

本轮在 main 的原生 UI 改造基础上进一步核对 Apple 平台指南，修复设置导航、标准快捷键、辅助功能摘要、长内容布局和中文漏项。验收环境为 macOS 27.0.1（26A434）、Xcode 27.0（27A266a）。用户选择隔离模拟；全局辅助功能和外观设置没有改变，真实邮件账户和安装版没有替换。

## 本轮修复

| 区域 | 问题与最终处理 |
| --- | --- |
| Settings | 旧 Sidebar 导航改为真正的 AppKit `.preference` NSToolbar。七个分类不可定制、不可隐藏，当前分类为窗口标题及系统选中项，恢复最近分类；最小化和缩放操作禁用。保留已访问 pane 的 HostingView，切换不丢未保存输入。 |
| Settings 导航完整性 | 实机发现仅设置 allowsUserCustomization=false 仍允许辅助功能移除或重排项目。使用原生 toolbarImmovableItemIdentifiers 与 canBeInsertedAt 委托保护全部七项；删除临时公共 mutation 锁子类。 |
| 系统菜单 | 应用菜单显示 EmailX；⌥⌘T 恢复系统工具栏显隐快捷键，会话分组改用 ⇧⌥⌘T。⌘N 通过 AppDelegate 路由，可从设置、阅读及写信窗口新建草稿。 |
| 邮件列表 | 装饰性文本、Circle 和 Flag 不再成为独立 AX 子元素；每行保留完整邮件摘要。长标题限制在单元格内，Return/Enter 打开选中邮件，系统键盘选行和类型选择保留。 |
| 独立阅读窗口 | 邮件实际加载后才启用回复、归档、删除等动作，初始及加载失败状态禁用；保留 UUID 的生产数据库 BLOB 查询兼容性。 |
| 阅读及 EML | 邮件头和附件改用原生滚动回退。邮件头最多占窗口内容高度 40% 且不超过 220pt，附件最多占 25% 且不超过 140pt；长主题、大量地址和附件不再挤掉正文。 |
| 写信附件 | 用 ViewThatFits 和系统 ScrollView，少量附件保留自然高度，大量附件最多 140pt；完整文件名和大小提供辅助功能信息，移除按钮保持原生样式及清晰名称。 |
| 写信与格式 | 收件人建议只在字段聚焦时出现；格式按钮和附件移除动作提供至少 20pt 的图标区域。文字颜色恢复正文 first responder，并使用原生 changeColor 响应链，避免共享颜色面板持有某个旧草稿的 target。 |
| 状态提示 | 错误、连接状态和新增失败操作使用原生辅助功能公告；保留 VoiceOver 开启时不自动隐藏错误的保护。 |
| 本地化 | String Catalog 补齐抄送／密送、消息列表、工具栏、密度和相关说明的简体中文。语言选项仍仅跟随 macOS／简体中文／English。 |

标准 Sidebar、Toolbar、List、Form、Button、Menu、Picker、TextField 等继续由系统渲染，不在正文或所有内容区叠加玻璃。现有 EmailXAppIcon.icon 多层图标继续由 Xcode 原生编译并被产物选择。

## 可重复验证

| 检查 | 结果及证明范围 |
| --- | --- |
| Release 构建及 codesign --verify --deep --strict | 通过；本地构建及签名完整，不代表发行公证。 |
| verify-settings-toolbar.sh | 编译生产设置宿主和分类视图，以简单 pane 替身检查七项原生导航、不可移动委托、窗口标题、选中状态、显隐及最小化/缩放菜单保护、pane 复用和最近分类恢复。 |
| verify-native-ui.sh | 生产 cell 复用、AX 摘要、装饰子项清理、长标题宽度、Return/Enter 激活、浅色/深色换行几何通过。 |
| verify-compose-toolbar.sh | 原生工具栏安装、菜单动作、响应状态、两个草稿隔离、Cmd+Return 可用/禁用状态及系统溢出项目通过。 |
| verify-native-layout.sh | 直接编译生产附件视图，1/40 个长文件名、560/900/1200pt、Aqua/Dark/两种增强对比度 NSAppearance，共 24 个组合通过。附件高度从原先 2052pt 限制到 140pt；这是几何模拟，不是像素对比度或真实 Show Borders 验收。 |
| verify-reading-layout.sh | 编译生产邮件头、EML 头和附件视图，使用数据/服务替身；280/500pt、100 行主题和大量地址/附件通过。长头原始高度 2404pt，EML 7909/5123pt，在测试容器中限制到 134pt，附件限制到 84pt，正文空间得以保留。 |
| verify-background-scheduling.sh | 其他账户 IDLE 存续、60 秒轮询、重叠合并、5 分钟回退和 App Nap 活动保护通过。 |
| verify-message-list.sh | 完整会话、历史可达性、固定分页、排序、旗标更新、新邮件立即进入列表、快速切换不接受旧回调通过。 |

脚本位于 scripts；运行时编译和合成文件写入临时目录，不访问真实邮件容器。阅读布局替身不执行邮件 HTML、不连接网络，也不能证明所有真实协议路径。

## 隔离实例运行结果

运行使用独立 bundle ID com.chengsen.EmailX.NativeUIProbe、独立容器、.invalid 合成账户和缓存邮件。启动同步对测试域名产生预期 DNS 失败，操作失败队列属于合成数据，不作为真实收信失败或收信成功证据。未发送任何邮件。

实机控件树和交互验证了：中文邮件列表、无装饰性 Circle/Flag AX 子项、回车打开独立阅读窗口、阅读窗口工具栏显隐、七分类设置工具栏、设置工具栏不能隐藏、设置按钮不再暴露 AX 移动/移除动作、设置页未保存规则名称在切换后保留、设置页内 Cmd+N 新建草稿、中文抄送／密送入口，以及无收件人时发送动作禁用。通过原生附件选择面板导入两份合成文件，正文仍存在，完整文件名和大小可读，移除第二份后第一份保留；40 附件场景由生产视图几何模拟验证。

此前整合轮已检查七个设置 pane、账户添加两条入口、规则和签名编辑、HTML 阻止远程内容、回复引用、调试分隔位置及原生多层图标编译。本轮在此基础上补验上述变更；此前覆盖见 native-ui-completion-2026-10-02.md，详细领域审计见 native-settings-audit.md、native-reading-audit.md、native-compose-status-audit.md。

## 明确的验收边界

模拟能够发现布局溢出、动作错误、可用状态和辅助功能树问题，不能替代真正开启 VoiceOver 后的朗读顺序、完整键盘控制、Show Borders、减少透明度／动态效果的全流程测试。SwiftUI accessibilityShowBorders 是系统只读环境值，没有采用私有 API 假造它。原生组件承担系统适配；这不能被写成所有辅助功能组合均已实机通过。

颜色修改的 NSTextView 选区行为已用离线 AppKit probe 检查；后续原生异步事件循环 probe 已验证共享颜色面板在两个 key/main 草稿窗口间正确路由，鼠标颜色选择器全流程仍未完整验证。屏幕采集仅得到低分辨率窗口缩略图，无法支持像素级视觉、对比度或全部图标外观结论。

真实公司账户认证、收信及 SMTP 投递未在本轮重测。同步、协议、安全过滤、MIME、凭证和 MCP 服务层没有变更，现有调度与邮件列表检查通过。原有 Test Connection 按钮仍是日志占位；它不是连接测试成功证据。MCP 的真实 Codex 接入亦未在本轮验收。

因此可以确认当前已发现的原生 UI 代码问题已修复，列出的构建、模拟和隔离交互已通过；不能宣称获得 Apple 认证或百分之百覆盖全部系统与辅助功能组合。

## 依据

- [Apple Settings HIG](https://developer.apple.com/design/human-interface-guidelines/settings)：macOS 设置使用不可定制、始终可见的分类工具栏、当前分类标题，禁用最小化和缩放。
- [Apple Keyboards HIG](https://developer.apple.com/design/human-interface-guidelines/keyboards/)：标准快捷键与键盘导航。
- [Apple Accessibility HIG](https://developer.apple.com/design/human-interface-guidelines/accessibility)：有意义的标签、控件目标区域及实际辅助技术检查。
- [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)：优先使用系统组件及分层内容与交互。
- [accessibilityShowBorders](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityshowborders)：遵循系统边框偏好。
