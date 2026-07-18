#!/usr/bin/env bash
# 发行版检测与包管理适配

# 导出:
#   DISTRO_ID       e.g. ubuntu, debian, alpine
#   DISTRO_ID_LIKE  e.g. debian
#   DISTRO_VERSION  e.g. 22.04
#   DISTRO_FAMILY   debian | ubuntu | alpine | rhel | arch | suse | unknown
#   PKG_MGR         apt | apk | dnf | yum | pacman | zypper | unknown
#   INIT_SYSTEM     systemd | openrc | unknown

detect_distro() {
  DISTRO_ID=""
  DISTRO_ID_LIKE=""
  DISTRO_VERSION=""
  DISTRO_FAMILY="unknown"
  PKG_MGR="unknown"
  INIT_SYSTEM="unknown"

  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    DISTRO_ID="${ID:-}"
    DISTRO_ID_LIKE="${ID_LIKE:-}"
    DISTRO_VERSION="${VERSION_ID:-}"
  fi

  local blob
  blob="$(echo "${DISTRO_ID} ${DISTRO_ID_LIKE}" | tr '[:upper:]' '[:lower:]')"

  if echo "${blob}" | grep -q "alpine"; then
    DISTRO_FAMILY="alpine"
    PKG_MGR="apk"
  elif echo "${blob}" | grep -Eq "ubuntu"; then
    DISTRO_FAMILY="ubuntu"
    PKG_MGR="apt"
  elif echo "${blob}" | grep -Eq "debian"; then
    DISTRO_FAMILY="debian"
    PKG_MGR="apt"
  elif echo "${blob}" | grep -Eq "centos|rhel|fedora|rocky|alma|oracle|amzn"; then
    DISTRO_FAMILY="rhel"
    if command -v dnf >/dev/null 2>&1; then
      PKG_MGR="dnf"
    else
      PKG_MGR="yum"
    fi
  elif echo "${blob}" | grep -Eq "arch|manjaro|endeavouros"; then
    DISTRO_FAMILY="arch"
    PKG_MGR="pacman"
  elif echo "${blob}" | grep -Eq "suse|opensuse|sles"; then
    DISTRO_FAMILY="suse"
    PKG_MGR="zypper"
  else
    # 兜底：根据包管理器猜
    if command -v apk >/dev/null 2>&1; then
      DISTRO_FAMILY="alpine"
      PKG_MGR="apk"
    elif command -v apt-get >/dev/null 2>&1; then
      DISTRO_FAMILY="debian"
      PKG_MGR="apt"
    elif command -v dnf >/dev/null 2>&1; then
      DISTRO_FAMILY="rhel"
      PKG_MGR="dnf"
    elif command -v yum >/dev/null 2>&1; then
      DISTRO_FAMILY="rhel"
      PKG_MGR="yum"
    elif command -v pacman >/dev/null 2>&1; then
      DISTRO_FAMILY="arch"
      PKG_MGR="pacman"
    elif command -v zypper >/dev/null 2>&1; then
      DISTRO_FAMILY="suse"
      PKG_MGR="zypper"
    fi
  fi

  if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
    INIT_SYSTEM="systemd"
  elif command -v rc-service >/dev/null 2>&1 || [[ -d /etc/init.d ]]; then
    INIT_SYSTEM="openrc"
  fi

  export DISTRO_ID DISTRO_ID_LIKE DISTRO_VERSION DISTRO_FAMILY PKG_MGR INIT_SYSTEM
}

# 安装基础包（按包名列表，自动映射）
# 用法: pkg_install curl ca-certificates bash
pkg_install() {
  detect_distro
  local pkgs=("$@")
  [[ ${#pkgs[@]} -eq 0 ]] && return 0

  case "${PKG_MGR}" in
    apt)
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -y
      apt-get install -y "${pkgs[@]}"
      ;;
    apk)
      apk update
      apk add --no-cache "${pkgs[@]}"
      ;;
    dnf)
      dnf install -y "${pkgs[@]}"
      ;;
    yum)
      yum install -y "${pkgs[@]}"
      ;;
    pacman)
      pacman -Sy --noconfirm "${pkgs[@]}"
      ;;
    zypper)
      zypper --non-interactive install -y "${pkgs[@]}"
      ;;
    *)
      err "不支持的包管理器: ${PKG_MGR}"
      return 1
      ;;
  esac
}

# 打印当前系统信息
print_distro_info() {
  detect_distro
  info "系统: ${DISTRO_ID:-unknown} ${DISTRO_VERSION:-} (family=${DISTRO_FAMILY}, pkg=${PKG_MGR}, init=${INIT_SYSTEM})"
}

# 检查是否为受支持的主流系统
is_supported_distro() {
  detect_distro
  case "${DISTRO_FAMILY}" in
    ubuntu|debian|alpine|rhel|arch|suse) return 0 ;;
    *) return 1 ;;
  esac
}
