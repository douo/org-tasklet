# AGENTS.md

## 项目定位

`org-tasklet` 是一个轻量 Org todo list 跟踪插件，面向希望用 Org 文件管理任务、项目和收件箱的用户。

核心目标：

- 保留 inbox，但不要强制线性处理流程；通过单次命令处理光标所在的当前条目。
- 项目任务保留 `TODO -> NEXT -> DONE/CNCL` 状态流。
- 非项目任务只需要 `TODO -> DONE/CNCL`，不要强制 `NEXT`。
- 移除 `WAIT`。
- 保留 schedule、deadline、agenda、年度归档、浏览器稍后阅读、mode-line inbox 数量。
- 项目只使用 Org 树结构，不引入 DAG、依赖图或额外数据库。
- 模块懒加载，避免把 Org 大模块放进 Emacs 启动路径。

## 重要约束

- 不要连接或影响任何正在运行的 Emacs 进程。
- 验证统一使用独立 batch 命令，例如 `emacs -Q --batch` 或 `make test`。
- 不要用 `emacsclient`。
- 不要假设调用者的 Emacs 配置路径，也不要主动修改项目目录之外的配置文件。
- 代码中的说明性注释使用中文。
- 保持入口 `(require 'org-tasklet)` 轻量，不要在 `org-tasklet.el` 或 `org-tasklet-core.el` 顶层直接 `(require 'org)`。
- 编译产物 `*.elc`、`*.eln` 不应作为源码关注对象，已在 `.gitignore` 中忽略。

## 模块边界

- `org-tasklet.el`：入口、autoload、全局 minor mode、mode-line 刷新。
- `org-tasklet-core.el`：轻量配置、路径、文件初始化、计数、通用文本工具。不要在这里加载 Org。
- `org-tasklet-capture.el`：捕获 inbox、稍后阅读、打开数据文件。这里可以加载 Org。
- `org-tasklet-agenda.el`：agenda 总览、NEXT 视图、agenda 状态快捷切换。
- `org-tasklet-triage.el`：处理当前 inbox 条目的单次命令，以及打开 inbox 的便利入口。
- `org-tasklet-project.el`：项目树识别和 `NEXT` 状态刷新。
- `org-tasklet-archive.el`：年度 datetree 归档。
- `org-tasklet-protocol.el`：`org-protocol` 捕获兼容层。
- `org-tasklet-pkg.el`：包元数据，不纳入 native compile 的源码列表。
- `test/org-tasklet-test.el`：ERT 测试。
- `org-tasklet-help`：入口文件中的内置帮助命令，必须保持轻量，不要为了帮助加载 Org。

## 数据模型

默认数据目录由 `org-tasklet-directory` 控制，默认是 `~/org-tasklet`。

文件约定：

- `inbox.org`：临时收集区。
- `tasks.org`：正式任务和项目。
- `.archive/todo_YYYY.org`：年度归档文件。

状态约定：

- 全局状态序列：`TODO NEXT | DONE CNCL`。
- 开放状态：`TODO`、`NEXT`。
- 关闭状态：`DONE`、`CNCL`。
- `WAIT` 已明确移除，不要重新加入，除非用户重新决策。

项目识别：

- 标题有子任务，或属性 `TASKLET_PROJECT: t`，视为项目。
- 项目刷新只处理直接子任务。
- 没有 `NEXT` 时，把第一个未完成直接子任务设为 `NEXT`。
- 多个 `NEXT` 时，只保留第一个，其余改回 `TODO`。
- 不维护依赖图，不做全局 DAG 扫描。

## 浏览器协议

新协议名：`tasklet-capture`。

为了兼容历史浏览器脚本，继续支持协议名：`gtd-capture`。

注册入口是：

```elisp
(org-tasklet-register-org-protocol)
```

注意：只有调用该命令时才加载 `org-protocol`，不要在入口文件顶层加载。

## inbox 整理

不要为 inbox 引入会长期生效的整理状态，也不要接管 `m`、`d`、`c` 等普通字符键。
整理入口应是一次性命令：把光标放在某个 Org subtree 的标题或正文里，调用 `org-tasklet-triage-current-item`，选择分类，然后只处理当前 item。
不要再新增线性处理流程入口。

分类整理规则参考 org-gtd，但实现必须保持轻量：

- `Action`：单步任务，移动到 `tasks.org` 的 `Actions` 顶层分类下，并保持 `TODO`。
- `Project`：多步项目，移动到 `Projects` 顶层分类下；项目根标题不强制 TODO，直接子任务使用 `TODO/NEXT` 状态流。
- `Add to Project`：把当前 inbox item 作为子任务追加到用户选择的已有项目下，并刷新该项目的 `NEXT`。
- `Calendar`：需要出现在 agenda 的任务，移动到 `Calendar`；不要专门做设置日期动作，用户直接编辑 Org 文本里的 `SCHEDULED`、`DEADLINE` 或时间戳。
- `Habit`：定期习惯，移动到 `Habits`，并写入 Org 原生 `STYLE: habit`。
- `Tickler`：有明确提醒时间、以后再看的条目，移动到 `Tickler`，不写 org-gtd timestamp 属性。
- `Incubate`：没有明确时间承诺的以后可能事项，移动到 `Incubate`；兼容 `Someday`、`Someday/Maybe` 作为顶层标题别名。
- `Reference`：参考资料，移动到 `Reference`。
- `Quick Action`：已经立即处理完的条目，标记 `DONE` 后归档。
- `Trash`：不需要的条目，标记 `CNCL` 后归档。

tags 是整理流程的一部分。交互调用时使用 Org 自带的 tags 编辑命令；测试或 Lisp 调用可以给 `org-tasklet-triage-current-item` 传入 tags 参数。
整理过程不要写入 `ORG_GTD`、`ORG_GTD_REFILE`、`ORG_GTD_PROJECT_IDS` 等 org-gtd 元数据。
不要为了日期、排期、截止日期、priority、effort 之类信息新增整理菜单动作；这些信息保持普通 Org 文本编辑。

## 常用验证命令

在项目根目录运行：

```sh
make test
make compile
make native-compile
make measure
```

推荐完整验证：

```sh
make clean && make test && make compile && make test && make native-compile && make measure
```

当前已知基准：

```text
make test: 23/23 passed
require-org-tasklet: 约 0.009s 到 0.013s
features-added=5
loaded-org=nil
loaded-org-agenda=nil
loaded-org-capture=nil
loaded-org-protocol=nil
```

如果 `make native-compile` 第一次运行后 `make measure` 偶尔出现一次较高值，通常是 native-comp 首次加载或缓存生成影响。复测 `make measure` 三次，看稳定值。
`make test`、`make compile`、`make native-compile` 和 `make measure` 都会设置 `load-prefer-newer`，避免开发时旧 `.elc` 遮住更新后的源码。

## 内置帮助

`M-x org-tasklet-help` 必须能看到：

- 常用命令。
- inbox 分类整理规则。
- `Add to Project` 的语义。
- 不写 org-gtd 元数据的约束。
- 预编译命令 `make compile` 和 `make native-compile`。
- 预编译不会连接或影响正在运行的 Emacs 进程。

该帮助入口在 `org-tasklet.el` 中实现，不能让 `(require 'org-tasklet)` 提前加载 `org`。

## 性能守则

- 入口文件只允许加载 `org-tasklet-core` 和轻量 mode-line 逻辑。
- 需要 Org 的功能必须放在按命令加载的模块里。
- mode-line 只统计 inbox，默认不启用定时器。
- 项目刷新使用显式命令，不默认挂到每次保存或 TODO 状态变化。
- archive、agenda、protocol 都应保持懒加载。
- 新增功能时同步考虑 `make measure` 输出，不要让 `loaded-org` 从 `nil` 变成 `t`。

## 集成方式

本项目不自动修改任何外部 Emacs 配置。用户可以按自己的包管理方式加载，也可以在本地开发时临时加入 `load-path`：

```elisp
(add-to-list 'load-path "/path/to/org-tasklet")
(require 'org-tasklet)

;; 按需设置任务数据目录；默认值是 `~/org-tasklet'。
(setq org-tasklet-directory "~/org-tasklet")
(org-tasklet-setup)
(org-tasklet-mode 1)
```

协议捕获可按需加入：

```elisp
(with-eval-after-load 'org-protocol
  (org-tasklet-register-org-protocol))
```

如果需要浏览器协议立即可用，才显式加载：

```elisp
(require 'org-protocol)
(org-tasklet-register-org-protocol)
```

## 当前测试覆盖

`test/org-tasklet-test.el` 覆盖：

- 基础文件创建。
- 稍后阅读捕获写入 inbox。
- inbox 计数兼容没有 TODO 关键字的普通旧标题。
- 项目刷新把第一个子任务提升为 `NEXT`。
- 缺少 `NEXT` 的项目识别。
- 已关闭条目年度归档。
- 旧 `gtd-capture` 协议兼容。
- 新旧协议注册。
- 内置帮助包含分类整理和预编译说明。
- triage 按分类移动 inbox 条目到 tasks。
- triage 移动普通旧标题时自动补 `TODO`。
- 当前 inbox item 的单次分类处理命令。
- tags 是整理流程的一部分，且不会写入 org-gtd 元数据。
- 新建项目会移动到 `Projects`，直接子任务使用 `NEXT/TODO` 状态流。
- `Add to Project` 会把当前 item 追加到选中的项目下。
- `Calendar` 保留用户手写的 Org 日期文本。
- `Habit` 使用 `STYLE: habit`，默认移动到 `Habits` 顶层标题。
- `Tickler` 与 `Incubate` 会清理 TODO 状态并移动到各自分类。
- `Quick Action` 与 `Trash` 会分别标记 `DONE`/`CNCL` 后归档。
- 普通 Org 文件和 inbox 文件头区域不能执行当前 item 处理。

新增功能时优先补 ERT 测试，并保持 `emacs -Q --batch` 可运行。

## 后续优先事项

合理的下一步通常是：

- 提供通用导入工具，把其他 Org todo 文件映射到 `inbox.org` 和 `tasks.org`。
- 提供可选的快捷键配置示例，但不要自动修改外部配置。
- 增强 triage 体验，例如批量分类、项目选择和 tags 处理。
- 增加项目树导航和项目列表视图，但不要引入 DAG。
- 持续用 `make measure` 监控入口加载。
