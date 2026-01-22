# 🛠️ Ollama 模型管理与资源监控文档 (ollama_list)
-------------------------------------

## 1. 工具概述

`ollama_list` 是一个集成化的管理工具，旨在解决官方 `ollama list` 命令信息分散的问题。它通过关联 `list`（本地库）与 `ps`（运行态）的信息，并结合系统内存深度解析，为用户提供一个直观的“资源看板”。

## 2. 核心算法说明

### A. 显存资源池 (VRAM Pool)

根据 AMD Radeon 8060S (64GB VRAM + 32GB GTT) 的硬件特性，工具设定了统一的逻辑资源池：

$$
Total_Pool=VRAM\left(64GB\right)+GTT\left(32GB\right)=96GB
$$

* **计算逻辑**：从 `ollama ps` 获取运行中模型占用的显存大小，并从 96GB 的总量中扣除，实时反馈剩余可用空间。
    

### B. 系统内存解析 (System RAM)

工具通过读取 `/proc/meminfo` 获取底层数据：

* **Total RAM**: 物理内存总量（128GB）。
    
* **Available RAM**: 系统当前真正可用的内存（包含缓存释放预估）。
    
* **OS Overhead**: 计算公式为  $Total−Available$ 。这反映了操作系统、驱动程序及其他后台服务（非 Ollama 模型）消耗的资源。
    

## 3. 输出字段定义

| 字段名CSVJSONMarkdown | 说明 | 备注 |
| --- | --- | --- |
| ID | 模型哈希的短 ID (12位) | 用于唯一识别模型版本 |
| SHORT_NAME | 模型的简短名称 | 不含镜像站前缀的纯净名 |
| IN_RAM | 模型当前在显存/内存中的实际占用 | 绿色高亮表示模型正在活跃运行 |
| SIZE | 模型的磁盘占用大小 | 存储在/storage/models的大小 |
| MIRROR_URL | 模型的完整拉取路径 | 区分daocloud或registry.ollama.ai |

## 4. 资源看板示例 (Resource Dashboard)

文档记录的典型输出格式如下：

```Plaintext
    📊 资源概览 (128GB 物理内存)
    ------------------------------------------------------------
    🖥️  GPU VRAM 共享池:    96.0 GB
    🧠 AI 模型当前占用:    32.0 GB (Active)
    🚀 可用 VRAM 空间:     64.0 GB
    ------------------------------------------------------------
    📉 系统可用内存:       105.2 GB (OS+后台应用占用: 22.8 GB)
    ------------------------------------------------------------
```

## 5. 安装与维护

该工具已集成至 `github-tools` 自动化管理框架：

* **安装路径**: `/usr/local/bin/ollama_list`
    
* **更新指令**: `sudo github-tools update ollama_list`
    
*   **依赖项**: `bc`, `awk`, `ollama`, `grep`
    
