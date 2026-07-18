#!/usr/bin/env bash
# 任意机器一键入口：拉取仓库到本地后启动菜单 / 指定组件
#
# ========== 公开仓库（推荐）==========
#   bash <(curl -fsSL https://raw.githubusercontent.com/leeger/1key/main/bootstrap.sh)
#   或:
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/leeger/1key/main/bootstrap.sh)"
#
# 直接装某个组件（跳过主菜单）:
#   bash <(curl -fsSL https://raw.githubusercontent.com/leeger/1key/main/bootstrap.sh) yoyo
#   bash <(curl -fsSL https://raw.githubusercontent.com/leeger/1key/main/bootstrap.sh) 233boy
#   bash <(curl -fsSL https://raw.githubusercontent.com/leeger/1key/main/bootstrap.sh) bbr
#   bash <(curl -fsSL https://raw.githubusercontent.com/leeger/1key/main/bootstrap.sh) bbr onekey
#   bash <(curl -fsSL https://raw.githubusercontent.com/leeger/1key/main/bootstrap.sh) swap
#
# ========== 私有仓库 ==========
#   export GITHUB_TOKEN=ghp_xxxx   # 需有 repo 权限
#   bash <(curl -fsSL -H "Authorization: token ${GITHUB_TOKEN}" \
#     https://raw.githubusercontent.com/leeger/1key/main/bootstrap.sh)
#
# 环境变量:
#   REPO_URL      默认 https://github.com/leeger/1key.git
#   REPO_BRANCH   默认 main
#   INSTALL_DIR   默认 /opt/1key（非 root 时用 $HOME/.1key）
#   GITHUB_TOKEN  私有库克隆 / 下载用
#   FORCE_UPDATE  设为 1 时强制 git pull 更新

set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/leeger/1key.git}"
REPO_BRANCH="${REPO_BRANCH:-main}"
GITHUB_TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-}}"

if [[ "$(id -u)" -eq 0 ]]; then
  INSTALL_DIR="${INSTALL_DIR:-/opt/1key}"
else
  INSTALL_DIR="${INSTALL_DIR:-${HOME}/.1key}"
fi

info() { echo -e "\033[1;34m[INFO]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }
err()  { echo -e "\033[1;31m[ERR]\033[0m $*" >&2; }

# ---------- 基础依赖 ----------
need_cmd() { command -v "$1" >/dev/null 2>&1; }

install_pkgs() {
  local pkgs=("$@")
  if need_cmd apt-get; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y "${pkgs[@]}"
  elif need_cmd apk; then
    apk update
    apk add --no-cache "${pkgs[@]}"
  elif need_cmd dnf; then
    dnf install -y "${pkgs[@]}"
  elif need_cmd yum; then
    yum install -y "${pkgs[@]}"
  else
    err "无法自动安装依赖: ${pkgs[*]}，请手动安装"
    return 1
  fi
}

ensure_tools() {
  local missing=()
  need_cmd curl || need_cmd wget || missing+=(curl)
  need_cmd git || missing+=(git)
  need_cmd bash || missing+=(bash)

  if [[ ${#missing[@]} -gt 0 ]]; then
    if [[ "$(id -u)" -ne 0 ]] && ! need_cmd sudo; then
      err "缺少: ${missing[*]}，且无 root/sudo，请先安装"
      exit 1
    fi
    info "安装依赖: ${missing[*]}"
    if [[ "$(id -u)" -eq 0 ]]; then
      install_pkgs "${missing[@]}"
    else
      sudo bash -c "$(declare -f install_pkgs need_cmd); install_pkgs ${missing[*]}"
    fi
  fi
}

# ---------- 克隆 / 更新仓库 ----------
auth_repo_url() {
  local url="$1"
  if [[ -n "${GITHUB_TOKEN}" ]]; then
    # https://github.com/owner/repo.git -> https://x-access-token:TOKEN@github.com/owner/repo.git
    if [[ "${url}" =~ ^https://github.com/ ]]; then
      echo "${url/https:\/\//https://x-access-token:${GITHUB_TOKEN}@}"
      return 0
    fi
  fi
  echo "${url}"
}

fetch_repo() {
  local clone_url
  clone_url="$(auth_repo_url "${REPO_URL}")"

  mkdir -p "$(dirname "${INSTALL_DIR}")"

  if [[ -d "${INSTALL_DIR}/.git" ]]; then
    info "已存在安装目录: ${INSTALL_DIR}"
    if [[ "${FORCE_UPDATE:-0}" == "1" ]] || [[ ! -f "${INSTALL_DIR}/install.sh" ]]; then
      info "更新仓库 (${REPO_BRANCH})..."
      git -C "${INSTALL_DIR}" remote set-url origin "${clone_url}" 2>/dev/null || true
      git -C "${INSTALL_DIR}" fetch --depth 1 origin "${REPO_BRANCH}"
      git -C "${INSTALL_DIR}" checkout -B "${REPO_BRANCH}" "FETCH_HEAD"
    else
      # 默认也拉一次最新，失败不阻断（离线仍可用本地）
      if git -C "${INSTALL_DIR}" fetch --depth 1 origin "${REPO_BRANCH}" 2>/dev/null; then
        git -C "${INSTALL_DIR}" checkout -B "${REPO_BRANCH}" "FETCH_HEAD" 2>/dev/null || true
        info "已同步到最新 ${REPO_BRANCH}"
      else
        warn "无法在线更新，使用本地已有副本"
      fi
    fi
  else
    info "克隆仓库到: ${INSTALL_DIR}"
    rm -rf "${INSTALL_DIR}"
    if ! git clone --depth 1 --branch "${REPO_BRANCH}" "${clone_url}" "${INSTALL_DIR}"; then
      err "克隆失败。"
      err "若仓库是 Private，请先:"
      err "  export GITHUB_TOKEN=你的PAT"
      err "  然后重新执行一键命令"
      err "或把仓库改为 Public 后即可任意机器匿名使用。"
      exit 1
    fi
  fi

  # 克隆 URL 可能含 token，改回干净地址，避免泄露到 git config
  if [[ -n "${GITHUB_TOKEN}" ]]; then
    git -C "${INSTALL_DIR}" remote set-url origin "${REPO_URL}" 2>/dev/null || true
  fi

  chmod +x "${INSTALL_DIR}/install.sh" \
    "${INSTALL_DIR}/bootstrap.sh" \
    "${INSTALL_DIR}/scripts/singbox/"*.sh \
    "${INSTALL_DIR}/scripts/system/"*.sh 2>/dev/null || true
}

# ---------- 启动 ----------
run_target() {
  local target="${1:-menu}"
  cd "${INSTALL_DIR}"

  case "${target}" in
    menu|""|-|"install")
      info "启动交互菜单..."
      exec bash "${INSTALL_DIR}/install.sh"
      ;;
    yoyo|yyds)
      info "直接运行: sing-box yoyo"
      exec bash "${INSTALL_DIR}/scripts/singbox/yoyo.sh"
      ;;
    233boy|233)
      info "直接运行: sing-box 233boy"
      exec bash "${INSTALL_DIR}/scripts/singbox/233boy.sh"
      ;;
    bbr|bbrv3|onekey-bbr)
      info "直接运行: BBR / 网络加速"
      # bbr onekey / bbr enable / 无参进菜单
      if [[ "${target}" == "onekey-bbr" ]]; then
        exec bash "${INSTALL_DIR}/scripts/system/bbr.sh" onekey
      fi
      exec bash "${INSTALL_DIR}/scripts/system/bbr.sh" "${@:2}"
      ;;
    swap)
      info "直接运行: Swap"
      exec bash "${INSTALL_DIR}/scripts/system/swap.sh" "${@:2}"
      ;;
    timezone|tz|ntp)
      info "直接运行: 时区/NTP"
      exec bash "${INSTALL_DIR}/scripts/system/timezone.sh" "${@:2}"
      ;;
    net|netopt|net-optimize)
      info "直接运行: 网络 sysctl 优化"
      exec bash "${INSTALL_DIR}/scripts/system/net-optimize.sh" "${@:2}"
      ;;
    dns)
      info "直接运行: DNS"
      exec bash "${INSTALL_DIR}/scripts/system/dns.sh" "${@:2}"
      ;;
    -h|--help|help)
      cat <<EOF
用法:
  bootstrap.sh [menu|yoyo|233boy|bbr|swap|timezone|net|dns] [子命令...]

任意机器一键（公开仓库）:
  bash <(curl -fsSL https://raw.githubusercontent.com/leeger/1key/main/bootstrap.sh)
  bash <(curl -fsSL https://raw.githubusercontent.com/leeger/1key/main/bootstrap.sh) yoyo
  bash <(curl -fsSL https://raw.githubusercontent.com/leeger/1key/main/bootstrap.sh) bbr
  bash <(curl -fsSL https://raw.githubusercontent.com/leeger/1key/main/bootstrap.sh) bbr onekey

BBR 子命令示例:
  bbr onekey | enable | disable | status | apac | smart | byjoey

私有仓库:
  export GITHUB_TOKEN=ghp_xxx
  bash <(curl -fsSL -H "Authorization: token \${GITHUB_TOKEN}" \\
    https://raw.githubusercontent.com/leeger/1key/main/bootstrap.sh)
EOF
      exit 0
      ;;
    *)
      err "未知目标: ${target}（支持: menu | yoyo | 233boy | bbr | swap | timezone | net | dns）"
      exit 1
      ;;
  esac
}

main() {
  case "${1:-}" in
    -h|--help|help)
      run_target help
      return 0
      ;;
  esac

  info "1key 远程一键安装"
  info "仓库: ${REPO_URL} @ ${REPO_BRANCH}"
  info "目录: ${INSTALL_DIR}"

  ensure_tools
  fetch_repo
  # 透传全部参数：bootstrap.sh bbr enable / swap create 2G 等
  if [[ $# -eq 0 ]]; then
    run_target menu
  else
    run_target "$@"
  fi
}

main "$@"
