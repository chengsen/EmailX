# EmailX macOS 27 分支整合与验证

## 修改保存与整合

本地性能修复先保存为 `ebe62fa`，备份分支为 `codex/performance-before-ui-merge`。在 `codex/macos27-integration` 上通过合并提交 `15381f5` 整合远端 `ui/macos27-baseline` 的 `c1084e2`，没有改写历史、重置工作区或替换用户邮件库。

性能修复覆盖的 AppEnvironment、AppState、MessageListItem 和全部 Services 文件与 `ebe62fa` 完全相同。远端对消息列表视图的改动自动合并后，分页、排序、线程计数、最旧邮件可达性和入站显示检查继续通过。两条开发分支均保留完整提交历史。

## UI 补齐及整合故障修复

写信发送、附件、正文模式和签名迁入每窗口独立的 NSToolbar。格式栏保留为正文选区对应的 accessory 控件。原发送、草稿、签名和附件处理逻辑继续复用，Cmd+Return 保留并增加重复发送保护。

附件选择使用明确绑定所属写信窗口的非阻塞 NSOpenPanel sheet，不依赖 NSApp.keyWindow，其他窗口无需等待附件选择结束。实际操作发现旧 runModal 面板无法完成选择，改为 sheet 后已完成添加及移除。

实际主窗口检查发现 NavigationSplitView 在账户加载后覆盖 AppKit Toolbar。主窗口现在保留原工具栏，并仅在工具栏身份变化时恢复所有权；不使用定时轮询，不重建正常窗口更新中的项目。原生 Sidebar 开关、写信按钮和搜索入口均已实际检查。

附件预览、移除和收件人建议采用系统 bordered 按钮，移除正文静态附件区域的自定义玻璃。补充文件名、大小、动作标签和错误关闭说明。Escape 关闭建议，选择后恢复输入焦点。保留原有远程内容权限和状态动作。

新增有效多层 EmailXAppIcon.icon，Debug/Release 均选择新图标。最终构建含 EmailXAppIcon.icns，CFBundleIconName 为 EmailXAppIcon，assetutil 检查具有分层向量、图标组及不同外观。旧 PNG 仍可回退。制作方法和限制见 [app-icon.md](app-icon.md)。

远端使用的 SwiftUI `.card` 不支持 macOS，已改为 `.bordered`。不存在的 NSTableView `.lastColumnOnly` 已改为支持的 `.uniformColumnAutoresizingStyle`；单列摘要随窗口宽度调整。

## 运行与可执行检查

最终 arm64 Release 构建和 codesign 深度严格校验通过。日志位于 build/build-integration-final.log。Xcode 的 iOS CoreDevice/Simulator 插件提示未阻断 macOS 构建；图标编译器将 27.0.1 最低目标按 27.0 处理并给出提示。

以下生产源码检查通过：

- 全文索引重复启动、增量迁移、NULL 和九个索引字段变化、rowid、插入删除、评分旗标和未读计数。
- 2,400 封邮件、1,501 个线程的分页、全局排序、旧 UID 1 可达、选中行、旗标更新及入站显示。
- 32 MiB 二进制 MIME、中文头字段、CID、附件字节保真、文件名碰撞、quarantine、重新下载、文件 IO 错误和清理。解析耗时约 0.471 秒，主线程 heartbeat 解析期间 274 次，总计 289 次。
- 60 秒 STATUS、5 分钟兜底、重叠轮询合并、任务完成后下一轮恢复、启用账户的 App Nap 保护及其他账户 IDLE 生存。
- 原生写信 Toolbar 自动安装、双窗口状态隔离、所属附件窗口、菜单、禁用发送、Cmd+Return 和原生 overflow 项目结构。

通过隔离 bundle ID 的实际应用检查：设置入口、账户类型选择、IMAP 分组表单、主工具栏和 Sidebar 开关、写信入口、收件人及 Cc/Bcc 展开、发送按钮状态、纯文本切换、附件添加及移除。界面测试账户为禁用的 example.invalid 离线记录，没有凭据、实际连接或发送。该记录只存在于 IntegrationProbeAfter 测试容器；用户邮件容器未修改。

## 整合前后资源复测

对照版为先前性能修复产物，整合版为最终 Release 产物。两版分别使用独立新测试 bundle ID、空邮箱、默认偏好。进程及 lsof 确认隔离容器。App Launch 目标进程身份已核对。数据与原始 trace 在 build/IntegrationProfiling。

| 指标 | 整合前 | 最终整合版 |
| --- | --- | --- |
| 15 秒待机 footprint | 39.11–39.64 MiB | 37.74–39.03 MiB |
| 待机 CPU 加权平均 | 0.192% | 0.043% |
| 待机 CPU 最大采样 | 2.254% | 0.091% |
| 第一次新进程：框架初始化到 Foreground | 210.45 ms | 213.16 ms |
| 第二次新进程：同一阶段 | 204.31 ms | 220.33 ms |
| 8 秒归属应用进程的 GPU 执行区间 | 0 | 0 |

没有测出有意义的启动改善；样本只有每版两次，不能把数毫秒差异判定为稳定回退或提升。并非清空文件缓存后的冷启动，也不是点击图标到首屏可交互。App Launch 输出 sampling-period 提示、退出码 54，但生命周期记录及目标核验完整。

CPU 会受初始化和采样时点影响。中间 UI 版本的复测出现短时突增，随后回落；不能承诺以上 CPU 差异可稳定复现。内存基本同级，GPU 结果只说明这段空邮箱记录没有归属目标进程的执行区间，不代表系统 GPU 为零或图片邮件滚动已经验收。

数据库相同负载三次中位数：10,000 封重复 schema/migration 从旧基线的 408.991 ms 到当前的 0.136 ms；更新 1,000 条评分从 106.501 ms 到 15.148 ms。这是数据库操作指标，不是整应用启动倍数。

## 验收边界

本次构建、生产源码探针和上述离线 UI 操作通过。真实公司邮箱登录、收发、服务器断连重连及系统睡眠恢复尚未验证。VoiceOver 完整朗读、系统 Show Borders 各外观、长文本极限布局、实际 overflow 弹出菜单以及 Dock 各外观仍需专门验收，不能称为全应用最终视觉认证。详细辅助功能范围见 [ui-integration-accessibility.md](ui-integration-accessibility.md)。

新产物为 build/IntegrationDerivedData/Build/Products/Release/MyEmail.app。构建和测试没有替换安装版本，也没有退出 Thunderbird 或操作其公司邮箱会话。
