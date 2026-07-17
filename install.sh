#!/usr/bin/env bash
# ops-kit 主入口：交互菜单装机组件
# 用法:
#   bash install.sh
#   ./install.sh
#
# 每个子脚本也可独立运行，见 scripts/ 目录

set -euo pipefail

OPS_KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${OPS_KIT_ROOT}/lib/common.sh"
# shellcheck source=/dev/null
source "${OPS_KIT_ROOT}/lib/distro.sh"

VERSION="0.2.0"

run_script() {
  local script_path="$1"
  shift || true
  if [[ ! -f "${script_path}" ]]; then
    err "脚本不存在: ${script_path}"
    pause
    return 1
  fi
  if [[ ! -x "${script_path}" ]]; then
    chmod +x "${script_path}" || true
  fi
  # 不 set -e 传染到子脚本之外：捕获退出码
  set +e
  bash "${script_path}" "$@"
  local rc=$?
  set -e
  if [[ ${rc} -ne 0 ]]; then
    warn "脚本退出码: ${rc}"
  fi
  pause
  return 0
}

# ---------- 子菜单: sing-box ----------
menu_singbox() {
  local choice
  while true; do
    clear 2>/dev/null || true
    menu_header "sing-box 安装"
    print_distro_info
    echo ""
    echo "  1) sing-box yoyo (yyds)"
    echo "     独立命令: bash scripts/singbox/yoyo.sh"
    echo ""
    echo "  2) sing-box 233boy"
    echo "     独立命令: bash scripts/singbox/233boy.sh"
    echo ""
    menu_footer_back "返回上级"
    read_choice "请选择" choice || return 0

    case "${choice}" in
      1)
        run_script "${OPS_KIT_ROOT}/scripts/singbox/yoyo.sh"
        ;;
      2)
        run_script "${OPS_KIT_ROOT}/scripts/singbox/233boy.sh"
        ;;
      0)
        return 0
        ;;
      *)
        warn "无效选项: ${choice}"
        sleep 1
        ;;
    esac
  done
}

# ---------- 子菜单: 系统优化 / 网络 ----------
menu_system() {
  local choice
  while true; do
    clear 2>/dev/null || true
    menu_header "系统优化 / 网络"
    print_distro_info
    echo ""
    echo "  1) BBR 拥塞控制（内核原生）"
    echo "     独立命令: bash scripts/system/bbr.sh"
    echo ""
    echo "  2) Swap 管理"
    echo "     独立命令: bash scripts/system/swap.sh"
    echo ""
    echo "  3) 时区 / 时间同步"
    echo "     独立命令: bash scripts/system/timezone.sh"
    echo ""
    echo "  4) 网络 sysctl 优化"
    echo "     独立命令: bash scripts/system/net-optimize.sh"
    echo ""
    echo "  5) DNS 设置"
    echo "     独立命令: bash scripts/system/dns.sh"
    echo ""
    menu_footer_back "返回上级"
    read_choice "请选择" choice || return 0

    case "${choice}" in
      1) run_script "${OPS_KIT_ROOT}/scripts/system/bbr.sh" ;;
      2) run_script "${OPS_KIT_ROOT}/scripts/system/swap.sh" ;;
      3) run_script "${OPS_KIT_ROOT}/scripts/system/timezone.sh" ;;
      4) run_script "${OPS_KIT_ROOT}/scripts/system/net-optimize.sh" ;;
      5) run_script "${OPS_KIT_ROOT}/scripts/system/dns.sh" ;;
      0) return 0 ;;
      *)
        warn "无效选项: ${choice}"
        sleep 1
        ;;
    esac
  done
}

# ---------- 主菜单 ----------
menu_main() {
  local choice
  while true; do
    clear 2>/dev/null || true
    menu_header "1key 装机组件 v${VERSION}"
    print_distro_info
    echo ""
    echo "  1) sing-box 相关"
    echo "  2) 系统优化 / 网络"
    echo ""
    echo "  h) 帮助 / 独立运行说明"
    echo ""
    menu_footer_back "退出"
    read_choice "请选择" choice || exit 0

    case "${choice}" in
      1)
        menu_singbox
        ;;
      2)
        menu_system
        ;;
      h|H)
        show_help
        pause
        ;;
      0|q|Q)
        echo ""
        info "再见"
        exit 0
        ;;
      *)
        warn "无效选项: ${choice}"
        sleep 1
        ;;
    esac
  done
}

show_help() {
  cat <<EOF

1key 用法说明
=============

1) 任意机器远程一键（VPS）
   # 仓库需 Public；Private 需带 GITHUB_TOKEN
   bash <(curl -fsSL https://raw.githubusercontent.com/leeger/1key/main/bootstrap.sh)
   bash <(curl -fsSL https://raw.githubusercontent.com/leeger/1key/main/bootstrap.sh) yoyo
   bash <(curl -fsSL https://raw.githubusercontent.com/leeger/1key/main/bootstrap.sh) bbr
   bash <(curl -fsSL https://raw.githubusercontent.com/leeger/1key/main/bootstrap.sh) swap

2) 本机交互菜单
   bash install.sh

3) 独立运行某个组件
   sudo bash scripts/singbox/yoyo.sh
   sudo bash scripts/singbox/233boy.sh
   sudo bash scripts/system/bbr.sh
   sudo bash scripts/system/swap.sh
   sudo bash scripts/system/timezone.sh
   sudo bash scripts/system/net-optimize.sh
   sudo bash scripts/system/dns.sh

4) 菜单约定
   - 数字选择安装项
   - 每级菜单输入 0 返回上级；主菜单 0 退出

5) 系统支持
   - Ubuntu / Debian (apt)
   - Alpine (apk)
   - 系统优化脚本亦尽量兼容 RHEL 系

6) 注意
   - 多数安装脚本需要 root
   - sing-box 类为上游一键包装；系统优化类为 1key 自研
   - 请在合法合规场景下使用

项目路径: ${OPS_KIT_ROOT}

EOF
}

main() {
  # 非交互：打印帮助
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    show_help
    exit 0
  fi
  if [[ "${1:-}" == "-v" || "${1:-}" == "--version" ]]; then
    echo "1key ${VERSION}"
    exit 0
  fi

  detect_distro
  menu_main
}

main "$@"
