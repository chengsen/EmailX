# EmailX 启动与运行资源分析

2026-10-01，分析分支 `ui/macos27-baseline`，提交 `47def58195a86e09e95e7286b0ee52bfdb9e7b46`。使用 arm64 Release、macOS 27.0.1、Apple M5 Max（18 核 CPU、40 核 GPU）、128 GiB 统一内存。

当前空邮箱待机资源较低；主要可扩展性风险集中在数据库初始化、大文件夹全量列表更新和正文解析。没有证据支持以更换浏览器内核解决这些问题；当前正文渲染使用系统 WebKit。

## 实测与边界

采样进程 PID 83808。通过 vmmap、sample、Instruments Time Profiler（20 秒）、Activity Monitor（15 秒）及独立 ps 轮询获取数据，没有修改账户、邮件或应用偏好。数据库只读统计为 0 个账户、0 个文件夹、0 封邮件、0 个附件。

| 指标 | 结果 | 解释 |
| --- | --- | --- |
| 待机 CPU | Activity Monitor 有效记录平均 0.019%，最高 0.166%；独立 ps 20 次记录均四舍五入为 0.0% | 空邮箱待机，没有收发或解析任务；不是大邮箱负载结果 |
| CPU 时间增量 | Activity Monitor 首末记录间 11.83 秒增加 2.82 ms；空闲唤醒增加 4 次 | 该窗口内未见持续忙循环 |
| 实际内存 footprint | 70.55–70.63 MiB；vmmap 显示峰值约 71.7 MiB | 采用系统实际物理占用口径；不将共享框架映射全部算作独占内存 |
| RSS | 约 162.25 MiB | 包含共享页面，与 footprint 是不同口径，不能相加 |
| 主线程 | 5 秒 sample 的主线程采样均落在事件循环等待 | 仅说明这段空闲窗口，没有证明打开邮件时不会卡顿 |
| GPU | 未获得可靠的单应用 GPU 百分比 | powermetrics 需要管理员权限；当前 Activity Monitor trace 不提供 GPU 字段，也没有进行大图邮件滚动测试 |
| 冷启动 | 尚无可靠墙钟耗时 | 当前应用已在运行，重启授权问题仍待回复；没有重启系统或清除文件缓存 |
| 热启动 | 尚无可靠墙钟耗时 | 必须区分常驻进程重开窗口、退出后的缓存重启与热打开已缓存邮件 |

应用关闭最后一个窗口不会退出：AppDelegate.swift:59–68。常驻重开复用 MainWindowController（AppDelegate.swift:107–114），成本远低于退出后重启。后者仍执行全部数据库初始化，不能用前者的速度代表它。

## 启动路径的卡点

**优先级 1：每次启动重建全文索引。** AppDelegate.swift:15 在主线程构造 AppEnvironment；AppEnvironment.swift:57 初始化 DatabaseService.shared。DatabaseService.swift:57–61 同步执行建表、迁移与回填，之后才创建主窗口。DatabaseService+Schema.swift:58–73 每次调用 FTS5 synchronize(withTable:)，索引包含正文和 2/3/4/5 字符前缀。当前 GRDB VirtualTableModule.swift:182–184 即使虚拟表已存在也调用 didCreate，FTS5.swift:281 执行 rebuild。因此窗口出现前的工作量随邮件正文规模增长，退出后热缓存重启也不能跳过。应将索引创建与旧数据回填移入一次性 migration，后续由触发器维护；真正修改索引结构时再执行受控重建。

**优先级 2：每次启动扫描所有邮件主题。** DatabaseService+Schema.swift:41–45 无条件执行 TRIM 清洗 UPDATE。即使没有脏数据，也要逐行判断。应一次性清洗旧数据，并在新增数据时规范化。独立测试显示其成本低于全文重建，不能将两者同等排序。

**加载完成状态也存在问题。** ContentView.swift:84–89 启动文件夹 observation 后立即读取 folders，而 AppState.swift:319–322 在 MainActor Task 中延后赋值。首次启动可能跳过默认 Inbox 选择，表现为空列表；这是源码确定的竞态风险，尚未用有账户的运行界面复现。多个账户的 initialSync 还逐个 await，同步完成时间会受最慢账户影响，但网络 await 本身不阻塞主线程。

## 运行时的卡点

**优先级 3：热打开邮件会触发不必要的数据库与列表工作。** SyncService+Body.swift:36 在检查正文缓存前更新 interaction_score。该列属于 AppState.swift:209 的列表 observation。实际数据库触发器是 AFTER UPDATE ON messages，没有限定变更列，所以只改评分、已读或旗标，也会删除并重建这封邮件的全文索引，包括 body_text。热打开网络成本很低，也可能触发数据库写入和列表刷新。应仅在索引列变化时维护 FTS，并将阅读评分更新与常规列表显示更新解耦；仍需保留搜索排序和状态同步正确性。

**优先级 4：大文件夹数据模型没有分页。** 普通文件夹 observation 无 LIMIT（AppState.swift:193–198），随后 fetchAll（:238）。统一收件箱上限为 500，但普通文件夹会驻留全部 metadata。每次 MessageListTable.body 重建全量字典和数组（:131–132），NSTable 更新又生成全量 ID 数组、扫描选择（MessageListNSTable.swift:166–185）。表格虚拟化只减少可见单元格数量，不能限制模型内存或这些 O(N) 操作。已有后台 SQL 查询、正文不进入列表、排序缓存和可见行刷新保护；下一步应限制载入窗口并增量更新，而非再叠加一层视图缓存。

**优先级 5：MIME 解析和附件落盘占用主线程。** SyncService 为 MainActor（SyncService.swift:27），Body.swift:129 的 EmailMessage(data:) 和 :301 的 Data.write 是同步执行。大附件邮件会同时保留原始 RFC822、解析对象和解码数据，影响峰值内存与界面响应。预取有 30 封、1 MB/封、每批 5 封的保护，但手动打开不受该体积限制。应把解析和文件 IO 转到后台，再将数据库与界面结果安全提交。

**正文内存与 GPU 的主要来源是 WebKit 和图片。** 纯文本也包装为 HTML 使用 WKWebView（MessageDetailView.swift:179）。每个 CIDSchemeHandler 有 32 MB 原始图片软缓存，但这不限制 WebKit 解码后的位图。多窗口、大图与滚动可能增加 WebContent/GPU 服务占用；总资源应包括归属于 EmailX 的辅助进程。现有禁用 JS、相同 HTML 不重复加载、HTML 预处理后台执行的保护应保留。没有大图实测，暂不能断言 GPU 是当前主要瓶颈。可以优先评估纯文本的原生渲染和图片尺寸控制，不先替换整个渲染引擎。

**后台唤醒仍有节省空间。** AppEnvironment.swift:83 全生命周期持有 userInitiated activity，即使无账户也禁止 App Nap（SyncService+Connection.swift:54–58）。轮询为 60 秒 STATUS、5 分钟全刷新；无变化 MODSEQ 检查前仍更新文件夹计数。调试日志默认可见（RootView.swift:12），日志更新时筛选最多 5,000 条，同步密集时会增加 UI 工作。应按活动任务管理 App Nap，避免无变化数据库写入，默认隐藏调试面板；真实多账户轮询负载尚未采样。

## 独立数据库验证

测试使用独立合成数据库，复用实际应用的 FTS5 建表 SQL 和三个同步触发器。每封正文为 2,589 字节、300 个重复英文 token；没有读取或复制邮件内容。使用系统 Python sqlite3，结果是 SQL 层验证，不能当作 Swift UI 或真实邮箱端到端性能，也不能按倍数预测所有硬件。

| 模拟邮件数 | FTS 重建中位数（3 次） | 无脏数据主题扫描 | 更新 1,000 条评分，原触发器 | 限定 FTS 列后，同样更新 |
| --- | --- | --- | --- | --- |
| 1,000 | 23.59 ms | 0.22 ms | 69.73 ms | 7.06 ms |
| 10,000 | 319.13 ms | 6.63 ms | 96.44 ms | 5.65 ms |

1 万条记录时，评分更新的该轮差异约 17 倍，说明与正文无关的 UPDATE 重索引具有可避免成本。不能据此声称整款应用会快 17 倍。合成文本词汇重复、数据已处于缓存；长正文、多语言和更大邮箱需要另行验证。

## 下一步验收

先修复一次性索引初始化与无关 UPDATE 触发重索引，再做大列表增量加载和后台 MIME 解析。分别测量首次进程启动、退出后连续重启、常驻窗口重开，并以可交互首屏为终点。真正的冷文件缓存结果需要受控重启环境，不能靠单次退出重启命名为冷启动。

接入真实账户后，覆盖大文件夹切换、缓存邮件打开、未缓存大附件邮件、图片邮件滚动、持续同步和多窗口关闭后的内存回落。CPU/GPU 记录与邮件数量、正文大小、网络状态一并保存；主程序及归属辅助进程按 footprint 统计。当前完成的是空邮箱运行采样、静态路径核验与隔离 SQL 验证，尚未完成这些负载验收。

证据均在本机忽略目录 build：performance-vmmap.txt、performance-sample.txt、performance-idle.trace、performance-activity.trace、performance-activity-summary.json、performance-idle-metrics.json、performance-db-summary.json、performance-sql-benchmark.py、performance-sql-benchmark.json。未提交、未推送分析文件或性能 trace。
