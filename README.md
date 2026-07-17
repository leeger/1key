# ops-kit

意见化 / 菜单化装机组件集合：把常用一键脚本统一收纳，支持**交互菜单**与**单脚本独立运行**。

## 特性

- 每个组件有独立运行命令
- 主菜单选择安装，支持多级菜单
- **每级菜单输入 `0` 返回**（主菜单 `0` 退出）
- 适配 **Ubuntu / Debian / Alpine**（自动检测 `apt` / `apk`）
- 包装上游一键脚本，不篡改其交互流程

## 快速开始

```bash
# 克隆后
cd ops-kit
chmod +x install.sh scripts/singbox/*.sh

# 交互菜单
sudo bash install.sh
# 或
./install.sh
```

## 当前组件

### sing-box

| 菜单 | 说明 | 独立运行 |
|------|------|----------|
| yoyo (yyds) | [caigouzi121380/singbox-deploy](https://github.com/caigouzi121380/singbox-deploy) | `sudo bash scripts/singbox/yoyo.sh` |
| 233boy | [233boy/sing-box](https://github.com/233boy/sing-box) | `sudo bash scripts/singbox/233boy.sh` |

上游原始命令（本仓库等价包装）：

```bash
# yoyo
bash -c "$(curl -fsSL https://raw.githubusercontent.com/caigouzi121380/singbox-deploy/main/install-singbox-yyds.sh)"

# 233boy
bash <(wget -qO- -o- https://github.com/233boy/sing-box/raw/main/install.sh)
```

## 目录结构

```text
ops-kit/
├── install.sh                 # 主菜单入口
├── lib/
│   ├── common.sh              # 日志、确认、菜单、远程执行
│   └── distro.sh              # 发行版检测、包管理适配
├── scripts/
│   └── singbox/
│       ├── yoyo.sh            # 可独立运行
│       └── 233boy.sh          # 可独立运行
└── README.md
```

## 菜单示意

```text
ops-kit 装机组件
  1) sing-box 相关
  0) 退出

sing-box 安装
  1) sing-box yoyo (yyds)
  2) sing-box 233boy
  0) 返回上级
```

## 系统要求

- `bash`
- `curl` 或 `wget`（缺失时会在 Debian/Ubuntu/Alpine 上尝试自动安装 curl）
- 安装类操作通常需要 **root**

## 扩展新组件

1. 在 `scripts/<分类>/` 下新增可独立运行的 `xxx.sh`
2. `source lib/common.sh` 与 `lib/distro.sh`
3. 在 `install.sh` 对应子菜单中增加一项

## 免责声明

本项目仅为脚本聚合与菜单封装，**不包含**代理协议实现。请遵守当地法律法规与服务器提供商条款，仅在合法授权环境中使用。上游脚本版权归原作者所有。
