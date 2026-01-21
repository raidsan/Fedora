# github-tools.sh 功能说明文档

`github-tools` 是一个为 Linux 系统（尤其是 Fedora）设计的轻量级、自举式脚本管理工具。它通过追踪 GitHub 下载链接和 SHA256 哈希值，实现对运维脚本的快速安装、版本监控及自动化更新。

---

## 1. 核心特性

- **自动化安装**：支持通过 URL 一键安装脚本至 `/usr/local/bin`。
- **版本追踪**：自动记录每个工具的下载来源、更新时间及文件哈希。
- **镜像站适配**：支持并记录镜像加速链接（如 `gh-proxy.com`），确保后续更新依然走加速通道。
- **智能更新**：
  - `update`：一键检测并更新所有已安装工具。
  - `update <name>`：使用记录中的原始链接针对性更新指定工具。
- **自举更新**：具备自我更新能力，且在批量更新时自动将自身置于最后执行，确保更新过程不中断。
- **容错修复**：若元数据文件损坏，支持通过 `add` 命令直接覆盖重建。

---

## 2. 初次安装与自注册

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
---

## 3. 使用说明

### 3.1 帮助与版本信息
```bash
sudo github-tools help
# 或任意未知参数
sudo github-tools -v
```
显示参数说明及使用指南。

### 3.2 列出已安装工具
```Bash
sudo github-tools
```
不带参数执行时，将以表格形式展示已安装工具的更新时间、来源 URL 以及 HASH 简码。

### 3.3 新增/覆盖工具 (add)
```Bash
sudo github-tools add <URL>
```
* 安装：如果工具名不存在，则下载安装并创建版本信息。
* 覆盖：如果工具名已存在，则视为强制更新，并记录新的 URL（适用于切换镜像源）。

### 3.4 批量更新 (update)
```Bash
sudo github-tools update
```
脚本将遍历元数据目录，对比远程 Hash，发现变动则自动下载更新。更新顺序为：其他工具 -> github-tools 自身。

### 3.5 更新指定工具
```Bash
sudo github-tools update <工具名称>
```
例如：sudo github-tools update ollama_blobs。脚本会提取该工具最后一次记录的 URL 进行更新。

---

## 4. 参数规划表
| 参数 | 描述 |
| --- | --- |
| (无参数) | 查询并列出所有已安装的工具及其元数据。 |
| help, -v | 显示帮助信息；输入未知参数时也会先提示错误再显示此内容。 |
| add <URL> | 新增工具。若名称冲突，则更新现有工具并覆盖旧的 URL。 |
| update | 检查并更新所有工具。github-tools 自身会排在最后更新。 |
| update <NAME> | 指定工具名，从本地版本记录提取 URL 进行单独更新。 |

---

## 5. 文件存储逻辑
* 可执行文件路径：/usr/local/bin/
* 元数据存储路径：/usr/local/bin/github-tools-meta/
* 元数据文件格式：时间 \t URL \t HASH
    * 采用 追加模式 (Append) 写入，该文件实际上充当了该工具的更新历史日志。
    * 读取时始终以最后一行（最新记录）为准。

---

## 6. 异常处理
* 未知参数提示： 若输入 sudo github-tools abc，脚本会提示： 未知参数: abc 随后直接展示 help 内容。
* 损坏修复机制： 若 .version 文件内容不符合预期（如非 Tab 分隔或 URL 格式错误），列表将提示 损坏。此时只需运行 add <URL> 即可自动覆盖下载并重建正常的版本记录。
