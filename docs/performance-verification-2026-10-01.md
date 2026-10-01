# EmailX 性能修复与复测

2026-10-01，在 `ui/macos27-baseline` 上完成五项性能修复。基线为 `47def58`，优化版在测量时使用本地未提交的工作区代码；此后保存为 `ebe62fa`，完整备份于 `codex/performance-before-ui-merge`。最终 arm64 Release 构建成功，严格深度签名检查通过。优化产物位于 `build/PerformanceDerivedData/Build/Products/Release/MyEmail.app`，原有构建产物未覆盖。

## 五项修复

1. 已有全文索引不再每次启动重建；主题清洗移为一次性增量迁移。首次升级仍需清洗一次，新建索引仍需首次建库工作；不清空邮箱或附件。
2. FTS UPDATE 触发器使用 NULL 安全比较，仅在索引字段或 rowid 实际变化时更新。评分、已读、旗标、下载状态和相同文本写入不再重索引正文。原插入、删除、未读计数和搜索语义保留。
3. 大文件夹采用后台轻量全局排序／线程图，详细 metadata 固定每页 500 个线程，翻页不累积旧页。保留完整历史可达性、全局排序、线程展开和当前选中线程。评分不再触发普通列表观察，选择变化复用已缓存显示数组。旧文件夹回调使用 generation 校验；默认 Inbox 在首次文件夹结果到达后选择。
4. MIME 解析、正文和头字段提取、附件保存、重新下载及原有 UIDVALIDITY 附件清理移到并发执行器，保留账户串行锁和文件成功后数据库提交的顺序。整封 MIME 解析仍保留，不能据此宣称大附件峰值内存已降低。
5. 无启用账户时不再禁止 App Nap，启用账户仍保留收件保护；合并重叠的定时与每账户 STATUS 轮询；文件夹计数相同不写数据库。默认隐藏调试面板，已有显式显示偏好保留。删除某个账户只取消该账户的 IDLE，不打断其他账户。

收件 IDLE、60 秒 STATUS、5 分钟兜底刷新、网络恢复和系统唤醒入口继续保留，没有降低轮询频率。慢任务的重复触发合并为一次，不取消正在运行的收件或离线队列。

## 同口径复测

本机为 Apple M5 Max、128 GiB 统一内存、macOS 27.0.1。两版使用独立测试 bundle ID、相同空邮箱、默认偏好，先基线后优化顺序运行；运行路径和 SQLite 容器通过进程及 lsof 核实。测试不使用真实账户、真实邮件或凭据。原应用先前的约 70.6 MiB 占用属于不同窗口／偏好／运行历史，不能与本表的全新测试实例直接比较。

| 项目 | 基线 | 优化版 | 判断 |
| --- | --- | --- | --- |
| 空邮箱 footprint（Activity Monitor） | 46.24–46.74 MiB | 32.06–32.50 MiB | 该样本约减少 14 MiB，约 30% |
| 空邮箱待机 CPU 加权平均 | 0.086% | 0.103% | 均很低，没有测出有意义的 CPU 改善 |
| 待机 CPU 最高采样 | 0.275% | 0.458% | 短窗口波动，不能宣称峰值下降 |
| 首次测量的新进程：框架初始化到 Foreground | 277.47 ms | 239.73 ms | 每版一个样本，已有系统文件缓存 |
| 随后的新进程重启：同一阶段 | 238.85 ms | 216.11 ms | 每版一个样本，不代表常驻窗口重开 |
| 空邮箱 GPU | 8 秒内无归属应用进程的执行区间 | 同样无归属应用进程的执行区间 | 未证明 GPU 百分比变化；WindowServer 合成与其他应用负载排除 |

启动由 Instruments App Launch 的生命周期标记测量，从 System Interface Initialization 到 Foreground；不是点击图标到可交互首屏的端到端验收，也不是重启系统后冷文件缓存。首次启动和连续重启的样本量很小，不能保证同幅度的速度提升。App Launch 输出 sampling-period 警告及退出码 54，生命周期记录存在，目标已核实为测试实例；到达限时后结束的只是测试进程。早期未核实路径的启动探针记录已排除。

GPU 使用 Metal System Trace 采样。记录包含 Chrome、WindowServer 等其他进程的执行，按目标进程过滤后两版均没有归属区间。不能把系统 GPU 活动当作 EmailX 占用，也不能以这段空邮箱记录证明图片邮件滚动性能已验收。

## 数据库负载验证

编译真实历史／当前 DatabaseService 源码，使用相同 GRDB 对象与隔离 SQLite。每封模拟正文 2,589 字节；三次中位数，计时包含事务提交，首次建库和迁移不计入。

| 数据量与操作 | 基线 | 优化版 |
| --- | --- | --- |
| 1,000 封：重复 schema/migration | 26.466 ms | 0.111 ms |
| 10,000 封：重复 schema/migration | 383.169 ms | 0.132 ms |
| 1,000 封库：更新 1,000 条评分 | 65.829 ms | 13.370 ms |
| 10,000 封库：更新 1,000 条评分 | 100.219 ms | 13.977 ms |

这些是数据库操作数据，不能换算成整款应用的倍数提升。FTS 完整性、旧触发器升级、二次启动无 rebuild／重复清洗、九个索引列、NULL 双向变化、重音、rowid、插入删除、评分旗标与未读数量均通过真实源码验证。

## 其他可运行检查

- 生产 AppState／排序／线程代码，在临时库运行 2,400 封邮件、1,501 个线程，含 900 封大线程：分页往返、最旧 UID 1 可达、完整线程数、旗标响应、评分不触发 metadata 更新、全部排序、模拟入站记录立即显示、分页边界选择保留及快速文件夹切换均通过。
- 生产 MIME helper，Swift 6／默认 MainActor 隔离，处理 32 MiB 二进制邮件：中文头、正文、CID、字节保真、文件名碰撞、quarantine、重新下载、文件 IO 错误、目录清理通过。主线程 heartbeat 在解析期间 272 次、总计 288 次，该轮耗时约 0.470 秒，证明异步处理时主线程能够继续执行。
- 从实际生产源码提取调度方法运行验证：60 秒间隔保留、重叠轮询合并、5 分钟刷新保留、完成后后续轮询恢复；有账户时保留 App Nap 保护，删除一个账户不取消另一账户的实际 IDLE Task。
- 实际 STATUS 计数 SQL：无变化不写，新增邮件、已读变化及删除后的数量均正确。
- 46 项 SwiftMail 协议测试通过，覆盖增量 FETCH、MODSEQ、QRESYNC、部分 BODY.PEEK 校验、头字段回退及非 UTF-8 APPEND。
- Release 构建、codesign 深度严格校验、补充分页中文资源和 diff 空白检查通过。

## 保留的边界

完整 JWZ 线程语义需要全局轻量 ID／线程图；极大单线程及显式多选线程仍会额外载入完整成员 metadata。本次解决的是普通大文件夹全量详细模型和频繁热刷新；没有证明所有邮箱规模下内存存在固定上限。若实际大线程成为主要占用，需要成员级分页。

真实收发、带附件／图片的实际 UI 操作、系统睡眠恢复后的收件延迟仍未端到端验收。当前真实 EmailX 数据库没有账户，因此不能宣称公司邮箱已经验证。优化版未强制替换或重启当前运行版本；使用新构建需在保存草稿后自行正常退出旧版并打开新产物。当前运行版本可继续保持原有收件。

## 复现

```sh
scripts/verify-database-startup.sh build/PerformanceDerivedData
scripts/benchmark-database-startup.sh build/PerformanceDerivedData
scripts/verify-body-processing.sh build/PerformanceDerivedData
scripts/verify-message-list.sh build/PerformanceDerivedData
scripts/verify-background-scheduling.sh
python3 scripts/verify-background-counts.py
```

原始 trace 与指标位于 `build/Profiling`，数据库结果位于 `build/verification/database-benchmark`。完整构建日志为 `build/build-performance.log`，协议测试日志为 `build/package-tests-performance.log`。该记录描述原测量时的状态；源码、检查和文档随后随性能备份提交保存，构建日志和原始 trace 保留在本机的忽略目录。最新整合结果见 `docs/ui-integration-2026-10-02.md`。
