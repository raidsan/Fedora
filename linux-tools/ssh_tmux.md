# ssh_tmux.sh 功能说明文档

`ssh_tmux` 是一个用于增强远程登录体验的工具。它能确保在 SSH 连接断开后，服务器上的任务依然在 `tmux` 中持续运行。

---

## 1. 核心特性

- **无缝重连**：采用 `new-session -A` 逻辑，会话已存在则自动重连（Attach）。
- **多会话管理**：支持开启多个独立的持久化终端。
- **历史记录隔离**：每个具名会话拥有独立的 Bash 命令历史文件，互不干扰。
- **自动加载**：连入会话时，自动加载该会话专属的历史缓存。
- **脚本更新**：支持通过 `github-tools`升级管理。

---

## 2. 历史记录机制
- **存储路径**：`~/.tmux_history/ssh_[会话标识]`
- **工作原理**: 进入会话时，脚本通过 `HISTFILE` 环境变量隔离历史，并强制 Shell 在启动时执行 `history -r` 加载对应文件。
- **实时同步**：安装时会自动向 `~/.bashrc` (Bash) 或 `~/.profile` (Ash)`PROMPT_COMMAND="history -a; $PROMPT_COMMAND"` 实现命令历史实时保存，其他shell可能不支持。

---

## 3. 使用场景


### 场景 A：手动开启/接入指定会话
直接在终端输入命令：
```bash
ssh_tmux [会话标识]
```
示例：ssh_tmux data 将进入名为 ssh_data 的会话。

### 场景 B：远程命令直接调用（推荐）
在客户端执行 SSH 连接时直接指定进入某个会话，适合针对不同任务快速跳转：
```Bash
ssh user@remote_host -t "ssh_tmux [会话标识]"
```
* 示例：ssh lgw@amd395 -t "ssh_tmux backup"
* 注意：-t 参数是必须的，用于强制分配伪终端。

### 场景 C：登录自动触发
将以下行添加到服务器的 ~/.bashrc 末尾，实现全自动保护：
```Bash
# 仅在交互式终端且是 SSH 登录时启动
[ -t 0 ] && [ -n "$SSH_CONNECTION" ] && ssh_tmux
```

### 查看命令历史
各会话输入 `history` 命令时，仅显示本会话内的操作记录。

---

## 4. 安装与管理
### 4.1 初次安装
使用 github-tools 进行快速安装：
```Bash
sudo github-tools add linux-tools/ssh_tmux.sh
```

### 4.2 更新
```Bash
sudo github-tools update ssh_tmux
```

---

## 5. 常见操作说明
* 暂时离开会话（保持后台运行）：按 Ctrl + b，然后按 d。
* 彻底关闭会话：在会话内输入 exit。
* 查看所有 ssh 专属会话：
```Bash
tmux ls | grep ssh_
```

---

## 6. 常见问题
* Q: 为什么提示没有权限？
* A: 脚本安装在 /usr/local/bin，执行安装或更新需使用 sudo。

* Q: 远程调用时为什么要加 -t？
* A: tmux 需要一个交互式终端（TTY）才能运行，SSH 远程执行命令默认不分配 TTY，-t 参数可以强制开启。

---

## 7. 实现细节说明：
1. **命名逻辑**：明确了 `ssh_` 前缀的强制性，保证了你以后执行 `tmux ls` 时能一眼看出哪些是 `ssh_tmux` 管理的会话。
2. **远程调用支持**：在文档中强调了 `-t` 参数的重要性，这是实现 `ssh user@host -t "ssh_tmux id"` 的技术关键。
3. **环境判断**：脚本内增加了 `[ -t 0 ]` 判断，确保在非交互式脚本调用时不会误触发 tmux 导致程序卡死。

**下一步建议：**
你现在可以先在其中一台机器上部署这个脚本，然后尝试在你的本地电脑（或另一台服务器）上执行 `ssh 用户名@IP -t "ssh_tmux dev"` 来看看效果。
或者在ssh终端图形工具例如 xshell里的SSH远程命令选项里输入：bash -c "ssh_tmux [会话标识]"
