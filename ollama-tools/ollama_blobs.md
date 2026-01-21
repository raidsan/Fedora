# ollama_blobs.sh 功能说明文档

`ollama_blobs` 是一个用于 Ollama 模型管理的辅助工具。它能够扫描本地模型存储目录，列出模型标签（Model Tag）与核心权重数据（Data Blob）哈希值，帮助用户精准识别磁盘上的模型文件。还支持对模型标签根据关键字过滤，并支持单独返回模型存储绝对路径以便于提供给其他模型调用工具例如`llama-server`来调用。

---

## 1. 核心特性

- **关键字过滤**：支持通过模型名称关键字（如 `qwen`）快速筛选目标模型。
- **路径提取模式 (`--blob-path`)**：专为脚本调用设计，仅输出匹配模型的权重文件绝对路径，并自动隐藏所有表格装饰。
- **智能路径拼接**：自动探测 Ollama 模型根目录，并精准指向 `/blobs/sha256-xxx` 物理文件。
- **多镜像去重**：自动合并不同镜像站（如 DaoCloud 等）产生的重复清单，确保结果唯一。
- **权重优先提取**：利用 `mediaType` 过滤技术，确保提取的是数 GB 的 GGUF 权重文件，而非几 KB 的配置文件。

---

## 2. 安装与更新

推荐使用 `github-tools` 进行管理，以确保能够一键获取最新修复和功能。

### 2.1 安装
```bash
# 设置你的脚本地址
export BLOBS_URL=https://raw.githubusercontent.com/.../ollama_blobs.sh
# 使用 github-tools 注册安装
sudo github-tools add $BLOBS_URL
```

### 2.2 更新
```Bash
sudo github-tools update ollama_blobs
```
---

## 3. 使用场景

### 场景 A：交互式查询（全部列出）

```Bash
sudo ollama_blobs
```
输出示例
```Plaintext

    Ollama 模型根目录: /usr/share/ollama/.ollama/models
    
    MODEL TAG (Short)                                  DATA BLOB HASH
    -------------------------------------------------- ---------------------------------------------------------------------------
    deepseek-r1:32b                                    sha256-c7f3ea903b50b3c9a42221b265ade4375d1bb5e3b6b6731488712886a8c41ff0
    qwen2.5-coder:32b-instruct-q8_0                    sha256-d2cfb03097fa1dc3f533d767eb58006853fea239bb3ec4ebf5bcb74e0086bc9a
    tinyllama:latest                                   sha256-6331358be52a6ebc2fd0755a51ad1175734fd17a628ab5ea6897109396245362
```

### 场景 B：交互式查询（带过滤）
列出所有包含 deepseek 关键字的模型及其哈希：
```Bash
ollama_blobs deepseek
```

### 场景 C：自动化脚本调用 (获取路径)

获取指定模型的权重文件绝对路径，用于给 llama-server 或其他程序传参：
```Bash
ollama_blobs qwen2.5-coder:32b --blob-path
```
输出示例：/storage/models/blobs/sha256-d2cfb03097fa1dc3f533d767eb58006853fea239bb3ec4ebf5bcb74e0086bc9a

* 脚本调用示例：
```Bash
#!/bin/bash
# 自动查找并启动匹配的模型
MODEL_PATH=$(ollama_blobs "qwen2.5-coder" --blob-path)
COUNT=$(echo "$MODEL_PATH" | grep -c "sha256-")

if [ "$COUNT" -eq 1 ]; then
    llama-server -m "$MODEL_PATH" --port 8080
elif [ "$COUNT" -gt 1 ]; then
    echo "错误：匹配到多个模型，请提供更精确的名称。"
else
    echo "错误：未找到模型。"
fi
```

---

## 4. 参数说明
| 参数 | 描述 |
| --- | --- |
| (无参数) | 以表格形式列出所有本地已下载的模型。 |
| <关键字> | 模糊匹配模型标签（Model Tag）。例如 32b 会匹配所有 32b 模型。 |
| --blob-path | 路径提取模式。必须配合关键字使用，直接输出 Blob 的绝对路径，不带表头。 |

---

## 5. 存储路径探测逻辑
脚本会按照以下顺序自动寻找 Ollama 的存储位置，无需手动配置：
1. 进程注入变量：检查运行中的 ollama 进程环境变量 OLLAMA_MODELS。
2. 系统路径 A：/usr/share/ollama/.ollama/models (标准 Linux 安装)。
3. 系统路径 B：/var/lib/ollama/.ollama/models (Docker 或部分发行版)。
4. 用户Home目录：~/.ollama/models (手动运行安装)。

---

## 6. 技术细节

* **权重 Blob 识别逻辑**

Ollama 的模型由多个 Blob 组成（Config, License, System, Model Weights）。本脚本通过搜索 `application/vnd.ollama.image.model` 类型的层来提取哈希。这确保了显示的哈希值与 `/models/blobs/` 目录下的超大文件名完全对应。


*   **去重逻辑**：脚本内部使用 `{ ... } | sort -u` 处理。即使 `manifests` 目录下存在多份镜像站下载的清单文件，只要它们对应的 `Model Tag` 和 `Hash` 一致，输出结果就会合并。
    
---

## 7. 常见问题

*   **Q: 为什么显示的 HASH 和 `ollama list` 的 ID 不一样？**
    
*   **A**: `ollama list` 显示的是 Config ID（元数据哈希），而 `ollama_blobs` 显示的是 Data Blob 哈希（权重文件哈希）。后者才是占用磁盘空间的“本体”。

