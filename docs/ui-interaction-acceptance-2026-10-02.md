# EmailX UI 与交互补充验收

本轮从 main 的 macOS 27 原生 UI 改造继续验收写信、邮件阅读和 EML 阅读，发现并修复了真实交互及最小窗口布局缺陷。环境为 macOS 27.0.1（26A434）、Xcode 27.0（27A266a）。运行使用独立 bundle ID 和容器的 EmailXAcceptance.app，账户、邮件、联系人历史和附件均为合成数据。全局辅助功能设置、真实邮箱容器和用户安装版没有改变，未发送邮件。

## 修复结果

| 区域 | 发现的问题 | 最终处理 |
| --- | --- | --- |
| 插入链接 | 直接修改 textStorage 不进入原生撤销路径；一次撤销可能删除之前输入的字符，而非撤销链接。 | 使用 NSTextView.insertText，保留 sheet 打开时的选区，遵守编辑委托并恢复原有 typingAttributes。一次撤销恢复原文、属性及选区，重做恢复链接。 |
| 链接输入 | 默认 https:// 虽然没有主机，插入按钮仍可用。 | HTTP(S) 必须有主机，所有 URL 必须有 scheme 及 scheme 后的内容；继续接受合法 mailto、file 和其他原生 URL scheme。 |
| 正文辅助功能 | 富文本和纯文本正文缺少明确的编辑区域名称。 | 两种模式使用现有 String Catalog 的“邮件正文”标签。 |
| 收件人焦点 | ViewThatFits 的两个表单实例在建议高度变化时替换，导致输入焦点及建议消失。 | 保持一个原生 ScrollView 和一份表单；高度受限，但内容、状态及焦点保留。 |
| 收件人建议 | 辅助功能角色为 unknown；方向键不能进入候选。 | 保留原生 Button 角色和完整姓名/地址标签，启用原生焦点；上下方向键移动、回车确认、Escape 关闭。 |
| 连续添加收件人 | 返回 TextField 时系统全选已有值，下一次输入覆盖已选地址。 | 返回字段后将原生 field editor 光标放到末尾；只操作仍是 key 的所属窗口。 |
| 小窗口布局 | 原有 40% 邮件头加 25% 附件限制未计入全部固定控件，极端阅读场景正文仅 41pt；写信最小外框尺寸也包含 toolbar。 | 邮件头占内容高度最多 35%、附件最多 20%，并保留 220/140pt 上限。写信使用 contentMinSize 560×400；长错误提示最多占内容高度 10%。 |
| 阅读展开状态 | ViewThatFits 复制有状态邮件头和附件树，跨越高度阈值时可能重置展开状态及焦点。 | 邮件头、EML 头和阅读附件均保留单一原生 ScrollView。短内容仍使用自然高度，长内容可以滚动。 |

## 运行与可重复检查

隔离应用的实际交互已确认链接 sheet 的取消保留选区和正文焦点、空主机 URL 禁用插入、插入后的 Cmd+Z/Shift+Cmd+Z 恢复正确文本与选区。收件人建议保持输入焦点，暴露八个原生按钮，方向键可以选择，回车确认后继续输入保留已选地址，Escape 关闭候选并回到输入字段。

`scripts/verify-editor-interaction.sh` 编译生产 RichTextEditor，在真正的 NSApplication 异步事件循环中运行两个 NSTextView 窗口。检查 URL 校验、标签、链接插入、选区、输入属性、一次 Undo/Redo、编辑委托拒绝及其他草稿不变。两个真实 key/main 窗口之间切换后，nil-target NSColorPanel 的 changeColor 通过原生响应链只修改当前草稿的选区。该项通过，没有跳过；这是原生事件路由检查，不是鼠标操作颜色选择器的全流程验收。

`scripts/verify-recipient-interaction.sh` 编译最终生产 ComposeHeaderFields，在真实异步 AppKit 事件循环及 700×600 fixture 窗口中，通过窗口自身的 native keyDown 和 field editor 验证 Down/Down/Up/Return 的正确候选、光标回到末尾、继续输入保留旧地址、Escape 保留字段焦点，以及候选显示时 To→Subject 的 Tab。展开字段后，To→Cc→Bcc→Reply-To 的逐步 Tab 也通过。此检查使用生产 SwiftUI 表单，只有账户和联系人服务为合成替身；不是对用户应用发送系统键盘事件，也不是完整键盘控制或窄窗口离屏控件的全流程证明。最终共享焦点修改由该原生运行检查覆盖；屏幕采集失败期间未把最终 Tab 操作称为 CUA 实机点击验收。

`scripts/verify-native-layout.sh` 直接编译生产写信邮件头和附件视图，在 560/900/1200pt 宽度、Aqua/Dark/两种增强对比度 NSAppearance 下检查 24 个邮件头组合和 24 个附件组合。邮件头包含大量地址、长主题及展开的抄送字段；附件包含 1/40 个长文件名。全部保持在设定的 viewport 内。增强对比度 NSAppearance 是几何模拟，不能证明像素对比度或真实 Show Borders 效果。

`scripts/verify-reading-layout.sh` 编译完整生产 MessageDetailView 和 EmlViewerView。真实 fixture NSWindow 使用 unified toolbar，外框 500×400、内容高度 334pt；100 行主题、大量地址和 100 个附件场景中，邮件正文从 41pt 增至 74pt，EML 正文从 115pt 增至 148pt，均超过检查要求的 70pt。数据、服务和 HTML renderer 为隔离替身，因此不证明真实 HTML 渲染或协议运行。

原生工具栏和邮件 cell 检查分别由 `verify-compose-toolbar.sh`、`verify-native-ui.sh` 通过。Release 构建和严格签名检查通过。没有新增第三方依赖，也没有修改同步、协议、凭证、MIME、安全过滤或 MCP 服务层。

## 仍未取得的证明

本轮遵循用户选择，未开启全局 VoiceOver、Show Borders、完整键盘控制、减少透明度或减少动态效果。普通键盘交互与隔离外观/布局模拟可以发现本轮缺陷，但不能代替这些系统模式下的全流程验收。屏幕采集存在缩略图、部分窗口空白及 SCStream -3811，已有控件树与几何证据不足以宣称全部界面的像素级视觉、对比度和图标外观通过。

此前设置七分类、工具栏保护、未保存编辑保留、账户入口、附件导入及移除等交互证据见 [上一轮验收](macos27-design-acceptance-2026-10-02.md)。本报告补充本轮实际发现和验证结果，不把旧证据改写为本轮重新验收，也不宣称 Apple 认证或全部系统组合百分之百通过。
