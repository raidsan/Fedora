# 🛠️ Ollama 外部模型拉取与自动注册工具 (ollama_fetch)
-------------------------------------

## 1. 工具概述

`ollama_fetch` 是一个专为高性能 AI 主机设计的运维脚本。它解决了 Ollama 官方库模型更新慢、量化版本单一（多为 Q4）的问题。该工具支持从 Hugging Face 直接拉取任意 GGUF 模型，并利用本地存储挂载点进行高效中转，最后自动注入 Ollama 模型库。

## 2. 核心算法与设计逻辑

### A. 存储感知中转 (Storage-Aware Transit)
针对 **GTR9 Pro** 用户常将模型库挂载于大容量分区（如 `/storage/models`）的习惯：
* **路径探测**：脚本自动解析 `ollama.service` 环境变量或探测系统路径，定位模型库根目录。
* **空间对齐**：放弃使用系统默认的 `/tmp`（防止 60GB+ 的 FP16 模型撑爆根分区），改为在模型库同级目录下创建 `tmp`。
* **快速注入**：由于中转站与目标库在同一挂载点，`ollama create` 过程中的文件移动效率极高。

### B. 模型注入流程
1. **下载**：调用 `huggingface-cli` 获取指定量化位数的 `.gguf` 文件。
2. **构建**：自动生成临时 `Modelfile`，并预设针对 MoE 架构（如 Qwen3/GLM4）优化的参数。
3. **注册**：执行 `ollama create`，此时 Ollama 会将模型哈希化并纳入其官方 Blob 管理体系。

## 3. 参数说明

| 参数 | 描述 | 示例 |
| :--- | :--- | :--- |
| `<Repo>` | Hugging Face 仓库名。 | `ggml-org/Qwen3-Coder-30B-A3B-Instruct-Q8_0-GGUF` |
| `<Pattern>` | 文件匹配规则，用于筛选特定的量化版本。 | `"*.gguf"` 或 `"*Q8_0.gguf"` |
| `[Alias]` | (可选) 在 Ollama 中显示的简短别名。 | `qwen3-q8` |
| `-doc` | 显示本说明文档。 | `ollama_fetch -doc` |

---

## 4. 针对 128GB 内存主机的进阶用法

利用 **Radeon 8060S** 的显存能力，建议通过此工具部署以下“高智力”模型以匹配 1500 分基准表现：

### 拉取 GLM-4.7-Flash (Q8 精度)
```bash
ollama_fetch unsloth/GLM-4.7-Flash-GGUF "*Q8_0.gguf" glm4-flash

### 拉取 Qwen 3.0 Coder (FP16 原始精度)
```Bash
ollama_fetch Qwen/Qwen3-Coder-32B-Instruct-GGUF "*fp16.gguf" qwen3-fp16

---

## 5. 管理与维护
* **安装目录**: /usr/local/bin/ollama_fetch
* **元数据路径**: /usr/local/share/github-tools-meta/
* **管理规范**: 由 github-tools 统一负责 HASH 校验与版本同步。

---

## 6. 使用建议
1. **存放位置**：请确保将此文件保存为 `/usr/local/share/github-tools-meta/ollama_fetch.md`。
2. **权限检查**：由于你的 `ollama_fetch.sh` 脚本中使用了 `show_doc` 函数，确保该 `.md` 文件对普通用户是可读的。
3. **验证文档**：输入 `ollama_fetch -doc`，查看在你的终端（尤其是支持 `glow` 的环境下）显示效果是否符合预期。
