#!/usr/bin/env bash
# 设置系统 DNS（systemd-resolved / resolv.conf）
# 独立运行: sudo bash scripts/system/dns.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPS_KIT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=/dev/null
source "${OPS_KIT_ROOT}/lib/common.sh"
# shellcheck source=/dev/null
source "${OPS_KIT_ROOT}/lib/distro.sh"

RESOLV_BACKUP="/etc/resolv.conf.1key.bak"

# 预设
PRESET_CLOUDFLARE="1.1.1.1 1.0.0.1"
PRESET_GOOGLE="8.8.8.8 8.8.4.4"
PRESET_ALIYUN="223.5.5.5 223.6.6.6"
PRESET_DNSPOD="119.29.29.29 182.254.116.116"

show_status() {
  echo ""
  info "当前 DNS 相关状态"
  if command -v resolvectl >/dev/null 2>&1; then
    resolvectl status 2>/dev/null | head -n 40 || true
  elif command -v systemd-resolve >/dev/null 2>&1; then
    systemd-resolve --status 2>/dev/null | head -n 40 || true
  fi
  echo ""
  if [[ -f /etc/resolv.conf ]]; then
    info "/etc/resolv.conf:"
    grep -vE '^\s*(#|$)' /etc/resolv.conf 2>/dev/null || cat /etc/resolv.conf
  fi
  echo ""
}

using_resolved() {
  command -v systemctl >/dev/null 2>&1 \
    && systemctl is-active --quiet systemd-resolved 2>/dev/null
}

set_dns_list() {
  local servers=("$@")
  if [[ ${#servers[@]} -eq 0 ]]; then
    err "未提供 DNS 服务器"
    return 1
  fi

  if using_resolved && [[ -d /etc/systemd/resolved.conf.d || -f /etc/systemd/resolved.conf ]]; then
    mkdir -p /etc/systemd/resolved.conf.d
    {
      echo "# managed by 1key"
      echo "[Resolve]"
      echo "DNS=${servers[*]}"
      echo "FallbackDNS="
      # 避免 stub 与业务冲突时，仍保留 resolved
    } >/etc/systemd/resolved.conf.d/99-1key-dns.conf

    systemctl restart systemd-resolved 2>/dev/null || true

    # 确保 resolv.conf 指向 stub 或已由 resolved 管理
    if [[ -L /etc/resolv.conf ]] || [[ -f /etc/resolv.conf ]]; then
      ok "已通过 systemd-resolved 设置 DNS: ${servers[*]}"
      ok "配置: /etc/systemd/resolved.conf.d/99-1key-dns.conf"
      return 0
    fi
  fi

  # 直接写 resolv.conf
  if [[ -f /etc/resolv.conf && ! -f "${RESOLV_BACKUP}" ]]; then
    cp -a /etc/resolv.conf "${RESOLV_BACKUP}"
  fi

  # 若是 symlink 到 resolved stub，先处理
  if [[ -L /etc/resolv.conf ]]; then
    warn "/etc/resolv.conf 是符号链接，将备份并改为静态文件"
    cp -a /etc/resolv.conf "${RESOLV_BACKUP}.link" 2>/dev/null || true
    rm -f /etc/resolv.conf
  fi

  {
    echo "# managed by 1key — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    for s in "${servers[@]}"; do
      echo "nameserver ${s}"
    done
  } >/etc/resolv.conf
  chmod 644 /etc/resolv.conf
  ok "已写入 /etc/resolv.conf: ${servers[*]}"
}

restore_dns() {
  if [[ -f /etc/systemd/resolved.conf.d/99-1key-dns.conf ]]; then
    rm -f /etc/systemd/resolved.conf.d/99-1key-dns.conf
    systemctl restart systemd-resolved 2>/dev/null || true
    ok "已移除 systemd-resolved 1key DNS 配置"
  fi
  if [[ -f "${RESOLV_BACKUP}" ]]; then
    cp -a "${RESOLV_BACKUP}" /etc/resolv.conf
    ok "已从 ${RESOLV_BACKUP} 恢复 resolv.conf"
  else
    warn "无 resolv.conf 备份可恢复"
  fi
}

menu() {
  local choice
  while true; do
    clear 2>/dev/null || true
    menu_header "DNS 设置"
    print_distro_info
    show_status
    echo "  1) Cloudflare  1.1.1.1"
    echo "  2) Google      8.8.8.8"
    echo "  3) 阿里云      223.5.5.5"
    echo "  4) DNSPod     119.29.29.29"
    echo "  5) 自定义"
    echo "  6) 恢复 / 回滚 1key DNS"
    echo "  7) 仅查看状态"
    echo ""
    menu_footer_back "返回 / 退出"
    read_choice "请选择" choice || exit 0

    case "${choice}" in
      1) set_dns_list ${PRESET_CLOUDFLARE} || true; pause ;;
      2) set_dns_list ${PRESET_GOOGLE} || true; pause ;;
      3) set_dns_list ${PRESET_ALIYUN} || true; pause ;;
      4) set_dns_list ${PRESET_DNSPOD} || true; pause ;;
      5)
        local custom
        read -r -p "输入 DNS（空格分隔，如 1.1.1.1 8.8.8.8）: " custom
        # shellcheck disable=SC2086
        set_dns_list ${custom} || true
        pause
        ;;
      6) restore_dns || true; pause ;;
      7) show_status; pause ;;
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
  bash dns.sh                    # 交互菜单
  bash dns.sh cloudflare|google|aliyun|dnspod
  bash dns.sh set 1.1.1.1 8.8.8.8
  bash dns.sh restore
  bash dns.sh status
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
    cloudflare|cf)
      # shellcheck disable=SC2086
      set_dns_list ${PRESET_CLOUDFLARE}
      ;;
    google)
      # shellcheck disable=SC2086
      set_dns_list ${PRESET_GOOGLE}
      ;;
    aliyun|ali)
      # shellcheck disable=SC2086
      set_dns_list ${PRESET_ALIYUN}
      ;;
    dnspod)
      # shellcheck disable=SC2086
      set_dns_list ${PRESET_DNSPOD}
      ;;
    set|--set)
      shift
      set_dns_list "$@"
      ;;
    restore|--restore)
      restore_dns
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
