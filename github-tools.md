# github-tools.sh 功能说明文档

`github-tools` 是一个为 Linux 系统（尤其是 Fedora）设计的轻量级、自举式脚本管理工具。它通过追踪 GitHub 下载链接和 SHA256 哈希值，实现对运维脚本的安装、文档同步及自动化更新。

---

## 1. 核心特性

- **自动化安装注册**：支持通过 URL 一键安装脚本至 `/usr/local/bin`。
- **文档自动同步**：更新或添加脚本时，自动探测并同步同名的 .md 说明文档。
- **版本与 HASH 监控**：记录每个工具的下载来源、更新时间及文件哈希，确保代码一致性。
- **智能更新机制**：
  - `update`：一键对比远程 Hash，仅更新有变动的工具。。
  - `update <name>`：使用记录中的原始链接针对性更新指定工具。
- **自举更新**：具备自我更新能力，并在批量更新时自动将自身置于最后执行，确保管理程序始终最新。
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
curl -sL $TOOLS_URL | sudo bash -s -- $TOOLS_URL
```

### 2.2 帮助与版本信息
* 参数：help, -v 或任意未知参数
  显示参数说明及使用指南。
* -doc
  显示对应 md 文档
  
### 2.3 列出已安装工具
```Bash
sudo github-tools
```
不带参数执行时，将以表格形式展示已安装工具的更新时间、来源 URL 以及 HASH 简码。

### 2.4 新增/覆盖工具 (add)
```Bash
sudo github-tools add <URL>
```
* 脚本安装：如果工具名不存在，下载并安装脚本至 /usr/local/bin。
* 文档抓取：自动尝试下载 URL 同级目录下的 .md 文件（如 example.sh 对应 example.md）。
* 覆盖机制：如果工具名已存在，则视为强制更新，并记录新的 URL（适用于切换镜像源，文件所在网址目录变化）。

### 2.5 批量更新 (update)
```Bash
sudo github-tools update
```
脚本将遍历元数据目录，对比远程 Hash，发现变动则自动下载并同步新版文档。

### 2.6 更新指定工具
```Bash
sudo github-tools update <工具名称>
```
例如：sudo github-tools update ollama_blobs。脚本会提取该工具最后一次记录的 URL 进行更新。

---

## 3. 设计说明

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
| 元数据记录 | /usr/local/share/github-tools-meta/*.version | 记录 时间 \t URL \t HASH |
| 说明文档 | /usr/local/share/github-tools-meta/*.md | 供工具通过 -doc 参数调用 |

### 3.5 异常处理与偏好
* **损坏修复**：若 .version 文件内容不符合预期（如非 Tab 分隔或 URL 格式错误），列表将提示 损坏。此时只需运行 add <URL> 重新安装即可重建。
* **输出偏好**：脚本所有指令执行完毕后，会额外输出一个空行，确保输出内容与下一个命令提示符（Prompt）之间有清晰的视觉间隔，方便分析。
* **权限说明**：涉及安装、更新、写入元数据目录的操作必须使用 sudo。
