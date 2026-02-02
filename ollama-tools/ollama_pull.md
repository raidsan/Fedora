# 🚀 Ollama 模型拉取与国内加速工具 (ollama_pull)
-------------------------------------

## 1. 工具概述

`ollama_pull` 是一个专为解决国内环境下 Ollama 模型拉取困难、下载中断及标签管理混乱而设计的增强工具。它集成了多镜像源自动切换、断点续传机制，并引入了“短名称别名”逻辑，方便用户在 `aider` 或 `llama-server` 中通过简短名称调用长 URL 模型。

## 2. 核心特性

### A. 镜像加速与断点续传
针对大型模型（如 Qwen 3.0-32B-FP16 约 66GB），工具默认支持：
* **多源支持**：内置 `daocloud` (默认) 和 `nju` (南京大学) 镜像源。
* **自动重试**：网络波动导致连接中断时，脚本会自动进入 5 秒循环重试，直至下载完成。

### B. 智能别名机制 (Alias Logic)
为了解决镜像站拉取后模型名称过长（如 `ollama.m.daocloud.io/library/qwen3-coder:32b`）的问题：
1. **自动提取**：从长 URL 中提取核心模型名 `qwen3-coder:32b`。
2. **本地映射**：执行 `ollama cp`，将长名称映射为短名称。
3. **结果**：你可以直接通过 `ollama run qwen3-coder:32b` 运行，无需输入镜像前缀。

## 3. 参数说明

| 参数 | 描述 | 示例 |
| --- | --- | --- |
| `<model_name>` | 必填。需要拉取的模型名称或标签。 | `qwen3-coder:32b` |
| `-p=dao` | (默认) 使用 DaoCloud 镜像加速。 | `ollama_pull qwen:7b -p=dao` |
| `-p=nju` | 使用南京大学镜像加速。 | `ollama_pull qwen:7b -p=nju` |
| `-doc` | 显示本说明文档。 | `ollama_pull -doc` |

---

## 4. 管理与维护
安装目录: /usr/local/bin/ollama_pull

元数据存储: /usr/local/share/github-tools-meta/

管理工具: 由 github-tools 统一负责 HASH 校验与版本更新。
