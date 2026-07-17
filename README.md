# 1key

意见化 / 菜单化装机组件：把常用一键脚本收纳在一起，支持 **任意机器远程一键**、交互菜单、单脚本独立运行。

仓库：https://github.com/leeger/1key

## 任意机器一键（VPS / 云主机）

### 方式 A：公开仓库（推荐，真正「一键」）

先把仓库设为 **Public**（Settings → Danger Zone → Change visibility），然后在任意服务器执行：

```bash
# 交互菜单
bash <(curl -fsSL https://raw.githubusercontent.com/leeger/1key/main/bootstrap.sh)

# 或等价写法
bash -c "$(curl -fsSL https://raw.githubusercontent.com/leeger/1key/main/bootstrap.sh)"

# 直接装某个组件（跳过主菜单）
bash <(curl -fsSL https://raw.githubusercontent.com/leeger/1key/main/bootstrap.sh) yoyo
bash <(curl -fsSL https://raw.githubusercontent.com/leeger/1key/main/bootstrap.sh) 233boy
bash <(curl -fsSL https://raw.githubusercontent.com/leeger/1key/main/bootstrap.sh) bbr
bash <(curl -fsSL https://raw.githubusercontent.com/leeger/1key/main/bootstrap.sh) swap
```

无 `bash <(...)` 时可用：

```bash
curl -fsSL https://raw.githubusercontent.com/leeger/1key/main/bootstrap.sh | bash
curl -fsSL https://raw.githubusercontent.com/leeger/1key/main/bootstrap.sh | bash -s -- yoyo
```

> `bootstrap.sh` 会自动安装 `curl`/`git`（如需要），克隆到 `/opt/1key`（root）或 `~/.1key`，再启动菜单。

### 方式 B：私有仓库（当前若仍是 Private）

私有库 **不能** 匿名 `curl raw`，需要带 Token：

```bash
export GITHUB_TOKEN=ghp_你的PAT   # 需勾选 repo

# 下载 bootstrap + 克隆仓库都带鉴权
bash <(curl -fsSL -H "Authorization: token ${GITHUB_TOKEN}" \
  https://raw.githubusercontent.com/leeger/1key/main/bootstrap.sh)
```

或用 git 直接克隆后运行：

```bash
git clone https://x-access-token:${GITHUB_TOKEN}@github.com/leeger/1key.git /opt/1key
bash /opt/1key/install.sh
```

**说明：** 想在任何 VPS 上像 yoyo/233boy 那样随手一键，请使用 **公开仓库**。私有库每次都要带 Token，不适合当「通用一键」。

---

## 本机已克隆时

```bash
cd /path/to/1key
sudo bash install.sh

# 独立运行
sudo bash scripts/singbox/yoyo.sh
sudo bash scripts/system/bbr.sh
sudo bash scripts/system/swap.sh create 2G
```

## 特性

- 任意机器：`curl | bash` / `bash <(curl …)` 远程一键
- 每个组件可独立运行（多数支持子命令，便于自动化）
- 主菜单选择安装；每级菜单 **`0` 返回**（主菜单 `0` 退出）
- 适配 Ubuntu / Debian / Alpine（`apt` / `apk`）；系统优化类尽量兼容 RHEL
- sing-box 类包装上游一键脚本；系统优化类为 1key 自研、可回滚

## 当前组件

### sing-box

| 菜单 / 一键参数 | 说明 | 独立命令 |
|-----------------|------|----------|
| yoyo | [singbox-deploy yyds](https://github.com/caigouzi121380/singbox-deploy) | `scripts/singbox/yoyo.sh` |
| 233boy | [233boy/sing-box](https://github.com/233boy/sing-box) | `scripts/singbox/233boy.sh` |

上游原始命令：

```bash
# yoyo
bash -c "$(curl -fsSL https://raw.githubusercontent.com/caigouzi121380/singbox-deploy/main/install-singbox-yyds.sh)"

# 233boy
bash <(wget -qO- -o- https://github.com/233boy/sing-box/raw/main/install.sh)
```

### 系统优化 / 网络

| 菜单 / 一键参数 | 说明 | 独立命令 / 示例 |
|-----------------|------|-----------------|
| bbr | 启用内核原生 BBR + fq（不换第三方内核） | `scripts/system/bbr.sh enable` |
| swap | Swap 文件创建 / 删除 / swappiness | `scripts/system/swap.sh create 2G` |
| timezone | 时区 + NTP（chrony / timesyncd） | `scripts/system/timezone.sh shanghai` |
| net / net-optimize | 保守 sysctl 网络优化（可回滚） | `scripts/system/net-optimize.sh balanced` |
| dns | DNS 预设（CF / Google / 阿里 / DNSPod） | `scripts/system/dns.sh aliyun` |

## 目录结构

```text
1key/
├── bootstrap.sh               # 远程一键入口（任意机器）
├── install.sh                 # 主菜单入口
├── lib/
│   ├── common.sh
│   └── distro.sh
├── scripts/
│   ├── singbox/
│   │   ├── yoyo.sh
│   │   └── 233boy.sh
│   └── system/
│       ├── bbr.sh
│       ├── swap.sh
│       ├── timezone.sh
│       ├── net-optimize.sh
│       └── dns.sh
└── README.md
```

## 菜单示意

```text
1key 装机组件
  1) sing-box 相关
  2) 系统优化 / 网络
  0) 退出

系统优化 / 网络
  1) BBR 拥塞控制
  2) Swap 管理
  3) 时区 / 时间同步
  4) 网络 sysctl 优化
  5) DNS 设置
  0) 返回上级
```

## 环境变量（可选）

| 变量 | 默认 | 说明 |
|------|------|------|
| `REPO_URL` | `https://github.com/leeger/1key.git` | 仓库地址 |
| `REPO_BRANCH` | `main` | 分支 |
| `INSTALL_DIR` | `/opt/1key` 或 `~/.1key` | 克隆目录 |
| `GITHUB_TOKEN` | 空 | 私有库鉴权 |
| `FORCE_UPDATE` | `0` | `1` 时强制更新 |

## 系统要求

- `bash`
- 可访问 GitHub（或自备镜像 / Token）
- 安装类操作通常需要 **root**

## 扩展新组件

1. 在 `scripts/<分类>/` 新增可独立运行脚本  
2. `source lib/common.sh` 与 `lib/distro.sh`  
3. 在 `install.sh` 加菜单项，在 `bootstrap.sh` 的 `run_target` 加快捷参数  

## 免责声明

本项目仅为脚本聚合与菜单封装。请遵守当地法律法规与服务器条款，仅在合法授权环境中使用。上游脚本版权归原作者所有。
