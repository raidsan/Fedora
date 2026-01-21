# ssh_tmux.sh 功能说明文档

`ssh_tmux` 是一个用于增强远程登录体验的工具。它能确保在 SSH 连接断开后，服务器上的任务依然在 `tmux` 中持续运行。

---

## 1. 核心特性

- **多会话管理**：通过“会话标识”支持开启多个独立的持久化终端。
- **自动命名**：会话名遵循 `ssh_会话标识` 格式，易于识别。
- **无缝重连**：采用 `new-session -A` 逻辑，会话已存在则自动重连（Attach）。
- **零手动更新**：完全集成于 `github-tools`，支持一键批量升级。
- **自动安装依赖**：首次运行会自动探测并安装系统中的 `tmux` 软件。

---

## 2. 使用场景与用法


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

---

## 3. 安装与管理
### 3.1 初次安装
使用 github-tools 进行快速安装：
```Bash
sudo github-tools add https://raw.githubusercontent.com/.../ssh_tmux.sh
```

### 3.2 批量更新
```Bash
sudo github-tools update ssh_tmux
```

---

## 4. 常见操作说明
* 暂时离开会话（保持后台运行）：按 Ctrl + b，然后按 d。
* 彻底关闭会话：在会话内输入 exit。
* 查看所有 ssh 专属会话：
```Bash
tmux ls | grep ssh_
```

---

## 5. 常见问题
* Q: 为什么提示没有权限？
* A: 脚本安装在 /usr/local/bin，执行安装或更新需使用 sudo。

* Q: 远程调用时为什么要加 -t？
* A: tmux 需要一个交互式终端（TTY）才能运行，SSH 远程执行命令默认不分配 TTY，-t 参数可以强制开启。

---

## 6. 实现细节说明：
1. **命名逻辑**：明确了 `ssh_` 前缀的强制性，保证了你以后执行 `tmux ls` 时能一眼看出哪些是 `ssh_tmux` 管理的会话。
2. **远程调用支持**：在文档中强调了 `-t` 参数的重要性，这是实现 `ssh user@host -t "ssh_tmux id"` 的技术关键。
3. **环境判断**：脚本内增加了 `[ -t 0 ]` 判断，确保在非交互式脚本调用时不会误触发 tmux 导致程序卡死。

**下一步建议：**
你现在可以先在其中一台机器上部署这个脚本，然后尝试在你的本地电脑（或另一台服务器）上执行 `ssh 用户名@IP -t "ssh_tmux dev"` 来看看效果。
或者在ssh终端图形工具例如 xshell里的SSH远程命令选项里输入：bash -c "ssh_tmux [会话标识]"
