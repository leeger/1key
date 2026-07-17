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

VERSION="0.1.0"

run_script() {
  local script_path="$1"
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
  bash "${script_path}"
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

# ---------- 主菜单 ----------
menu_main() {
  local choice
  while true; do
    clear 2>/dev/null || true
    menu_header "ops-kit 装机组件 v${VERSION}"
    print_distro_info
    echo ""
    echo "  1) sing-box 相关"
    echo ""
    echo "  h) 帮助 / 独立运行说明"
    echo ""
    menu_footer_back "退出"
    read_choice "请选择" choice || exit 0

    case "${choice}" in
      1)
        menu_singbox
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

ops-kit 用法说明
================

1) 交互菜单（本脚本）
   bash install.sh
   或: ./install.sh

2) 独立运行某个组件（无需菜单）
   sudo bash scripts/singbox/yoyo.sh
   sudo bash scripts/singbox/233boy.sh

3) 菜单约定
   - 数字选择安装项
   - 每级菜单输入 0 返回上级；主菜单 0 退出

4) 系统支持
   - Ubuntu / Debian (apt)
   - Alpine (apk)
   - 其他系统会尽量检测并调用上游脚本（不保证成功）

5) 注意
   - 多数安装脚本需要 root
   - 本仓库仅包装上游一键脚本，具体逻辑以上游为准
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
    echo "ops-kit ${VERSION}"
    exit 0
  fi

  detect_distro
  menu_main
}

main "$@"
