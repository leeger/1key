#!/usr/bin/env bash
# 常用网络 / 系统 sysctl 优化（保守、可回滚）
# 独立运行: sudo bash scripts/system/net-optimize.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPS_KIT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=/dev/null
source "${OPS_KIT_ROOT}/lib/common.sh"
# shellcheck source=/dev/null
source "${OPS_KIT_ROOT}/lib/distro.sh"

SYSCTL_FILE="/etc/sysctl.d/99-1key-net.conf"

# 保守基线：提高连接跟踪与缓冲，开启 TCP 快速打开相关常见项
apply_profile() {
  local profile="${1:-balanced}"

  case "${profile}" in
    balanced|default)
      cat >"${SYSCTL_FILE}" <<'EOF'
# managed by 1key — balanced network profile
# 文件描述符 / 连接
fs.file-max = 1048576
net.core.somaxconn = 4096
net.core.netdev_max_backlog = 16384
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.ipv4.tcp_rmem = 4096 262144 16777216
net.ipv4.tcp_wmem = 4096 262144 16777216
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 10
# 可选：若内核支持且安全策略允许
# net.ipv4.tcp_fastopen = 3
EOF
      ;;
    minimal)
      cat >"${SYSCTL_FILE}" <<'EOF'
# managed by 1key — minimal network profile
net.core.somaxconn = 1024
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_fin_timeout = 30
net.ipv4.ip_local_port_range = 1024 65535
EOF
      ;;
    *)
      err "未知配置档: ${profile}（balanced | minimal）"
      return 1
      ;;
  esac

  # 应用；忽略个别键不存在
  set +e
  sysctl -p "${SYSCTL_FILE}" 2>/tmp/1key-sysctl.err
  local rc=$?
  set -e
  if [[ ${rc} -ne 0 ]]; then
    warn "部分 sysctl 项可能不被当前内核支持，详见 /tmp/1key-sysctl.err"
    # 逐行应用可应用项
    while IFS= read -r line || [[ -n "${line}" ]]; do
      [[ -z "${line}" || "${line}" =~ ^# ]] && continue
      sysctl -w "${line// /}" 2>/dev/null || sysctl -w "$(echo "${line}" | sed 's/ *= */=/')" 2>/dev/null || true
    done <"${SYSCTL_FILE}"
  fi

  # limits soft hint
  if [[ -d /etc/security/limits.d ]]; then
    cat >/etc/security/limits.d/99-1key-nofile.conf <<'EOF'
# managed by 1key
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
EOF
    ok "已写入 limits.d nofile 提示（需重新登录生效）"
  fi

  ok "已应用 ${profile} 配置 → ${SYSCTL_FILE}"
}

rollback() {
  if [[ -f "${SYSCTL_FILE}" ]]; then
    rm -f "${SYSCTL_FILE}"
    ok "已删除 ${SYSCTL_FILE}"
  else
    warn "未找到 1key 网络配置文件"
  fi
  rm -f /etc/security/limits.d/99-1key-nofile.conf 2>/dev/null || true
  sysctl --system >/dev/null 2>&1 || true
  ok "已回滚 1key 网络优化（重启后内核默认完全恢复更干净）"
}

show_status() {
  echo ""
  info "关键 sysctl 快照"
  for k in \
    net.core.somaxconn \
    net.ipv4.tcp_fin_timeout \
    net.ipv4.tcp_tw_reuse \
    net.ipv4.ip_local_port_range \
    net.ipv4.tcp_congestion_control \
    net.core.default_qdisc
  do
    local path="/proc/sys/${k//./\/}"
    if [[ -r "${path}" ]]; then
      echo "  ${k} = $(cat "${path}")"
    fi
  done
  if [[ -f "${SYSCTL_FILE}" ]]; then
    echo ""
    info "持久文件: ${SYSCTL_FILE}"
  else
    echo ""
    info "持久文件: 无"
  fi
  echo ""
}

menu() {
  local choice
  while true; do
    clear 2>/dev/null || true
    menu_header "网络 sysctl 优化"
    print_distro_info
    show_status
    echo "  1) 应用 balanced 配置（推荐）"
    echo "  2) 应用 minimal 配置"
    echo "  3) 回滚 1key 网络优化"
    echo "  4) 仅查看状态"
    echo ""
    echo "  说明: 不修改 BBR；BBR 请用「系统优化 → BBR」"
    echo ""
    menu_footer_back "返回 / 退出"
    read_choice "请选择" choice || exit 0

    case "${choice}" in
      1)
        if is_tty && ! confirm "应用 balanced 网络优化?"; then warn "已取消"; pause; continue; fi
        apply_profile balanced || true
        pause
        ;;
      2)
        if is_tty && ! confirm "应用 minimal 网络优化?"; then warn "已取消"; pause; continue; fi
        apply_profile minimal || true
        pause
        ;;
      3)
        if is_tty && ! confirm "确认回滚?"; then warn "已取消"; pause; continue; fi
        rollback || true
        pause
        ;;
      4) show_status; pause ;;
      0|q|Q) return 0 ;;
      *) warn "无效选项: ${choice}"; sleep 1 ;;
    esac
  done
}

main() {
  case "${1:-}" in
    -h|--help)
      cat <<EOF
用法:
  bash net-optimize.sh              # 交互菜单
  bash net-optimize.sh balanced     # 应用 balanced
  bash net-optimize.sh minimal
  bash net-optimize.sh rollback
  bash net-optimize.sh status
EOF
      return 0
      ;;
    status|--status)
      show_status
      return 0
      ;;
  esac

  require_root "$@"
  detect_distro

  case "${1:-}" in
    apply|balanced|--balanced)
      apply_profile balanced
      ;;
    minimal|--minimal)
      apply_profile minimal
      ;;
    rollback|--rollback|remove|--remove)
      rollback
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
