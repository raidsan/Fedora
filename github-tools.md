# github-tools.sh 功能说明文档

`github-tools` 是一个为 Linux 系统设计的轻量级脚本管理工具。它通过追踪 GitHub 下载链接和 SHA256 哈希值，实现安装、文档同步及自动化更新。

---

## 1. 核心特性

- **自动化安装注册**：支持通过 URL 一键安装脚本至 `/usr/local/bin`。
- **自动化初始化 (-init)**：更新后自动探测并执行脚本的初始化逻辑。
- **文档自动同步**：更新工具时，自动同步同名的 `.md` 说明文档。
- **规范化存储**：严格遵循 Linux 路径标准，分离可执行文件与共享元数据。

---

## 2. 使用说明

### 2.1 初次安装与自注册

由于初次安装通过管道执行，为了让脚本能够准确记录自身的下载源，请使用以下命令进行安装及自注册：

```bash
# 1. 设置源（官方源 或 镜像源）
export GITHUB=https://raw.githubusercontent.com
# 或 export GITHUB=https://gh-proxy.com/raw.githubusercontent.com

# 2. 设置仓库主路径
export MAIN=$GITHUB/raidsan/Fedora/refs/heads/main

# 3. 设置工具下载链接
export TOOLS_URL=$MAIN/github-tools.sh

# 4. 一键安装并自注册 (通过 bash -s 传递参数)
curl -sL $TOOLS_URL | <sudo> bash -s -- $TOOLS_URL
```

### 2.2 常用命令

* 列出工具：sudo github-tools。

* 新增工具：sudo github-tools add <URL>。

* 批量更新：sudo github-tools update。

* 查阅文档：netinfo -doc (需工具支持)。

---

## 3. 技术规范

### 3.1 参数规划表
| 参数 | 描述 |
| --- | --- |
| (无参数) | 查询并列出所有已安装的工具及其元数据。 |
| help, -v | 显示帮助信息；输入未知参数时也会先提示错误再显示此内容。 |
| add <URL> | 新增工具。若名称冲突，则更新现有工具并覆盖旧的 URL。 |
| update | 检查并更新所有工具。github-tools 自身会排在最后更新。 |
| update <NAME> | 指定工具名，从本地版本记录提取 URL 进行单独更新。 |

### 3.2 工具集成：查看文档 (-doc)
所有由 github-tools 管理的工具（如 netinfo, ollama_list 等），现在建议统一支持 -doc 参数。
运行示例：
```Bash
netinfo -doc
```
内部显示逻辑：
1. 优先调用 glow 进行终端 Markdown 美化渲染。
2. 若无 glow，尝试调用 ghostwriter 图形化界面。
3. 若均无，回退至 cat 纯文本显示。
    
### 3.3 文件存储规划
| 类型 | 路径 | 说明 |
| --- | --- | --- |
| 可执行文件 | /usr/local/bin/ | 系统级工具路径 |
| 元数据记录 | /usr/local/share/github-tools-meta/*.version | 记录格式：时间 \t <URL> \t HASH |
| 说明文档 | /usr/local/share/github-tools-meta/*.md | 供工具通过 -doc 参数调用 |

### 3.5 异常处理与偏好
* **损坏修复**：若 .version 文件内容不符合预期（如非 Tab 分隔或 URL 格式错误），列表将提示 损坏。此时只需运行 add <URL> 重新安装即可重建。
* **输出偏好**：脚本所有指令执行完毕后，会额外输出一个空行，确保输出内容与下一个命令提示符（Prompt）之间有清晰的视觉间隔，方便分析。
* **权限说明**：涉及安装、更新、写入元数据目录的操作必须使用 sudo。

### 3.6 脚本适配了 ash 语法和root运行环境
openwrt使用的ash 语法不支持 ==， d$'\t'

### 3.7 自动化初始化规范 (-init)

* 触发机制：github-tools 在安装或更新后，会检查脚本是否包含 -init 关键字。

* 执行逻辑：若匹配，则自动运行 script -init。这用于自动安装依赖（如 tmux）或写入环境变量（如 PROMPT_COMMAND）。
