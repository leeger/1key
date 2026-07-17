#!/usr/bin/env bash
# 启用内核原生 BBR + fq（不更换第三方内核）
# 独立运行: sudo bash scripts/system/bbr.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPS_KIT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=/dev/null
source "${OPS_KIT_ROOT}/lib/common.sh"
# shellcheck source=/dev/null
source "${OPS_KIT_ROOT}/lib/distro.sh"

SYSCTL_FILE="/etc/sysctl.d/99-1key-bbr.conf"

show_status() {
  echo ""
  info "当前状态"
  echo "  内核: $(uname -r)"
  if [[ -r /proc/sys/net/ipv4/tcp_congestion_control ]]; then
    echo "  拥塞控制: $(cat /proc/sys/net/ipv4/tcp_congestion_control)"
  fi
  if [[ -r /proc/sys/net/core/default_qdisc ]]; then
    echo "  默认队列: $(cat /proc/sys/net/core/default_qdisc)"
  fi
  if command -v modprobe >/dev/null 2>&1; then
    if lsmod 2>/dev/null | grep -q '^tcp_bbr'; then
      echo "  tcp_bbr 模块: 已加载"
    else
      echo "  tcp_bbr 模块: 未加载（可能已内建）"
    fi
  fi
  if [[ -f "${SYSCTL_FILE}" ]]; then
    echo "  持久配置: ${SYSCTL_FILE}"
  else
    echo "  持久配置: 无"
  fi
  echo ""
}

kernel_supports_bbr() {
  if [[ -d /lib/modules/$(uname -r)/kernel/net/ipv4 ]] || [[ -d /lib/modules/$(uname -r) ]]; then
    if modprobe -n tcp_bbr 2>/dev/null || grep -qw bbr /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
      return 0
    fi
  fi
  # 已可用即视为支持
  if grep -qw bbr /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
    return 0
  fi
  # 尝试加载
  if command -v modprobe >/dev/null 2>&1 && modprobe tcp_bbr 2>/dev/null; then
    return 0
  fi
  return 1
}

enable_bbr() {
  if ! kernel_supports_bbr; then
    err "当前内核似乎不支持 BBR（需要较新内核，如 4.9+）"
    err "可考虑升级系统内核后再试。本脚本不安装第三方魔改内核。"
    return 1
  fi

  # 尽量加载模块（内建时忽略失败）
  modprobe tcp_bbr 2>/dev/null || true

  if ! grep -qw bbr /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
    err "BBR 不在可用拥塞控制列表中: $(cat /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null || echo n/a)"
    return 1
  fi

  cat >"${SYSCTL_FILE}" <<'EOF'
# managed by 1key — BBR + fq
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF

  sysctl --system >/dev/null 2>&1 || sysctl -p "${SYSCTL_FILE}" >/dev/null

  # 立即生效（sysctl.d 已覆盖时再写一次保证）
  sysctl -w net.core.default_qdisc=fq >/dev/null
  sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null

  local cc qdisc
  cc="$(cat /proc/sys/net/ipv4/tcp_congestion_control)"
  qdisc="$(cat /proc/sys/net/core/default_qdisc)"
  if [[ "${cc}" == "bbr" ]]; then
    ok "已启用 BBR（qdisc=${qdisc}）"
    ok "配置已写入 ${SYSCTL_FILE}"
  else
    err "启用后拥塞控制仍为: ${cc}"
    return 1
  fi
}

disable_bbr() {
  # 恢复常见默认 cubic + fq_codel（若可用）
  local cc="cubic"
  local qdisc="fq_codel"
  if ! grep -qw cubic /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
    cc="$(awk '{print $1}' /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null || echo reno)"
  fi
  if ! grep -qw fq_codel /proc/sys/net/core/default_qdisc 2>/dev/null; then
    # 有的系统没有列表文件，直接尝试
    qdisc="fq_codel"
  fi

  rm -f "${SYSCTL_FILE}"
  sysctl -w "net.ipv4.tcp_congestion_control=${cc}" >/dev/null 2>&1 || true
  sysctl -w "net.core.default_qdisc=${qdisc}" >/dev/null 2>&1 || true
  sysctl --system >/dev/null 2>&1 || true
  ok "已移除 BBR 持久配置，当前: $(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null) / $(cat /proc/sys/net/core/default_qdisc 2>/dev/null)"
}

menu() {
  local choice
  while true; do
    clear 2>/dev/null || true
    menu_header "BBR 拥塞控制"
    print_distro_info
    show_status
    echo "  1) 启用 BBR + fq（内核原生，推荐）"
    echo "  2) 仅查看状态"
    echo "  3) 关闭 BBR（恢复 cubic 等默认）"
    echo ""
    menu_footer_back "返回 / 退出"
    read_choice "请选择" choice || exit 0

    case "${choice}" in
      1)
        if is_tty && ! confirm "确认启用 BBR + fq?"; then
          warn "已取消"
          pause
          continue
        fi
        enable_bbr || true
        pause
        ;;
      2)
        show_status
        pause
        ;;
      3)
        if is_tty && ! confirm "确认关闭 BBR?"; then
          warn "已取消"
          pause
          continue
        fi
        disable_bbr || true
        pause
        ;;
      0|q|Q)
        return 0
        ;;
      *)
        warn "无效选项: ${choice}"
        sleep 1
        ;;
    esac
  done
}

main() {
  case "${1:-}" in
    -h|--help)
      cat <<EOF
用法: bash bbr.sh [enable|disable|status]
  无参数进入交互菜单
EOF
      return 0
      ;;
    status|--status)
      detect_distro
      show_status
      return 0
      ;;
  esac

  require_root "$@"
  detect_distro

  case "${1:-}" in
    enable|--enable)
      enable_bbr
      ;;
    disable|--disable)
      disable_bbr
      ;;
    "")
      menu
      ;;
    *)
      err "未知参数: $1"
      exit 1
      ;;
  esac
}

main "$@"
