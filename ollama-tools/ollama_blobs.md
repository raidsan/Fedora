# ollama_blobs.sh 功能说明文档

`ollama_blobs` 是一个用于 Ollama 模型管理的辅助工具。它能够扫描本地模型存储目录，解析 Manifest 文件，并建立模型标签（Model Tag）与核心权重数据（Data Blob）哈希值之间的对应关系，帮助用户精准识别磁盘上的模型文件。

---

## 1. 核心特性

- **路径深度清理**：自动切除镜像站域名路径（如 `ollama.m.daocloud.io/`），仅保留模型核心标识。
- **智能前缀隐藏**：仿照 `ollama list` 逻辑，自动隐藏默认的 `library/` 前缀，使输出直观清晰。
- **核心哈希提取**：通过 `mediaType` 过滤，优先提取大小最大的模型权重层（Model Weights）哈希，而非几 KB 的配置文件哈希。
- **唯一化输出**：自动处理因不同镜像源下载导致的重复清单，确保每个模型标签只显示一行。
- **智能路径探测**：支持自动识别系统服务级（Systemd）、自定义路径（OLLAMA_MODELS）或用户家目录下的模型存储位置。

---

## 2. 初次安装与管理

建议使用 `github-tools` 进行安装，以便后续享受一键更新功能。

### 方式 A：通过 github-tools 安装（推荐）
```bash
# 假设你已设置好 $MAIN 变量
export BLOBS_URL=$MAIN/ollama_blobs.sh

# 使用 github-tools 新增工具
sudo github-tools add $BLOBS_URL
```

### 方式 B：直接 curl 管道安装
```Bash
curl -sL $BLOBS_URL | sudo bash
```
---

## 3. 使用说明

### 3.1 运行查询

```Bash
sudo ollama_blobs
```

### 3.2 输出示例
```Plaintext

    Ollama 模型根目录: /usr/share/ollama/.ollama/models
    
    MODEL TAG (Short)                                  DATA BLOB HASH
    -------------------------------------------------- ---------------------------------------------------------------------------
    deepseek-r1:32b                                    sha256-c7f3ea903b50b3c9a42221b265ade4375d1bb5e3b6b6731488712886a8c41ff0
    qwen2.5-coder:32b-instruct-q8_0                    sha256-d2cfb03097fa1dc3f533d767eb58006853fea239bb3ec4ebf5bcb74e0086bc9a
    tinyllama:latest                                   sha256-6331358be52a6ebc2fd0755a51ad1175734fd17a628ab5ea6897109396245362
```

---

## 4. 逻辑说明

### 4.1 权重 Blob 识别逻辑

Ollama 的模型由多个 Blob 组成（Config, License, System, Model Weights）。本脚本通过搜索 `application/vnd.ollama.image.model` 类型的层来提取哈希。这确保了显示的哈希值与 `/models/blobs/` 目录下的超大文件名完全对应。

### 4.2 存储路径探测顺序

脚本按以下优先级寻找 `models` 目录：

1.  **进程环境变量**：读取运行中 `ollama` 进程的 `OLLAMA_MODELS` 变量。
    
2.  **系统默认路径**：`/usr/share/ollama/.ollama/models` 或 `/var/lib/ollama/.ollama/models`。
    
3.  **用户家目录**：`~/.ollama/models`。

---

## 5. 技术实现细节

*   **去重逻辑**：脚本内部使用 `{ ... } | sort -u` 处理。即使 `manifests` 目录下存在多份镜像站下载的清单文件，只要它们对应的 `Model Tag` 和 `Hash` 一致，输出结果就会合并。
    
*   **格式化处理**：
    
    *   将哈希值中的冒号 `:` 替换为连字符 `-`（如 `sha256-xxx`），方便直接在文件系统中查找。
        
    *   模型简称列预留 50 字符宽度，适合长名称模型及各种 Tag 的对齐显示。

---

## 6. 常见问题

*   **Q: 为什么显示的 HASH 和 `ollama list` 的 ID 不一样？**
    
    *   **A**: `ollama list` 显示的是 Config ID（元数据哈希），而 `ollama_blobs` 显示的是 Data Blob 哈希（权重文件哈希）。后者才是占用磁盘空间的“本体”。
        
*   **Q: 如何更新此脚本？**
    
    *   **A**: 如果你是通过 `github-tools` 安装的，只需运行：
        
        ```Bash
        sudo github-tools update ollama_blobs
        ```
  
