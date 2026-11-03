#!/usr/bin/env bash
# ============================================================================
#  TEGUHSIBERSEC :: ProjectDiscovery Toolkit Installer
#  Tools   : nuclei | subfinder | httpx
#  Author  : teguhsibersec
#  Usage   : sudo bash install-pd-tools.sh
# ============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Konfigurasi
# ---------------------------------------------------------------------------
readonly VERSION="2.0"
readonly AUTHOR="teguhsibersec"
readonly MIN_GO_MINOR=24            # Go minimal 1.24
readonly LOG_FILE="/var/log/teguhsibersec-install.log"
readonly TOTAL_STEPS=6
STEP=0
START_TS=$(date +%s)

# ---------------------------------------------------------------------------
# Warna (dimatikan otomatis jika output bukan terminal)
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
  R=$'\e[0m';  B=$'\e[1m';  D=$'\e[2m'
  GRN=$'\e[38;5;46m';  CYN=$'\e[38;5;51m'
  RED=$'\e[38;5;196m'; YLW=$'\e[38;5;220m'; GRY=$'\e[38;5;244m'
else
  R=""; B=""; D=""; GRN=""; CYN=""; RED=""; YLW=""; GRY=""
fi

# ---------------------------------------------------------------------------
# UI helpers
# ---------------------------------------------------------------------------
banner() {
  clear 2>/dev/null || true
  echo -e "${GRN}${B}"
  cat <<'EOF'
  _____ _____ ____ _   _ _   _
 |_   _| ____/ ___| | | | | | |
   | | |  _|| |  _| | | | |_| |
   | | | |__| |_| | |_| |  _  |
   |_| |_____\____|\___/|_| |_|
EOF
  echo -e "${CYN}   ____ ___ ____  _____ ____  ____  _____ ____"
  cat <<'EOF'
  / ___|_ _| __ )| ____|  _ \/ ___|| ____/ ___|
  \___ \| ||  _ \|  _| | |_) \___ \|  _|| |
   ___) | || |_) | |___|  _ < ___) | |__| |___
  |____/___|____/|_____|_| \_\____/|_____\____|
EOF
  echo -e "${R}"
  echo -e "  ${GRY}────────────────────────────────────────────────────────${R}"
  echo -e "  ${B}ProjectDiscovery Toolkit Installer${R} ${D}v${VERSION}${R}"
  echo -e "  ${GRY}Tools  :${R} nuclei ${GRY}•${R} subfinder ${GRY}•${R} httpx"
  echo -e "  ${GRY}Author :${R} ${GRN}${AUTHOR}${R}"
  echo -e "  ${GRY}Log    :${R} ${LOG_FILE}"
  echo -e "  ${GRY}────────────────────────────────────────────────────────${R}"
  echo
}

step() {  # step "judul"
  STEP=$((STEP + 1))
  echo -e "\n${CYN}${B}[${STEP}/${TOTAL_STEPS}]${R} ${B}$1${R}"
}
info() { echo -e "  ${CYN}ℹ${R}  $1"; }
ok()   { echo -e "  ${GRN}✔${R}  $1"; }
warn() { echo -e "  ${YLW}⚠${R}  $1"; }
fail() { echo -e "  ${RED}✘${R}  $1" >&2; }

# Jalankan perintah di background dengan spinner; output masuk ke log
run() {  # run "pesan" cmd args...
  local msg="$1"; shift
  local frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  local i=0 pid
  "$@" >>"$LOG_FILE" 2>&1 &
  pid=$!
  if [[ -t 1 ]]; then
    while kill -0 "$pid" 2>/dev/null; do
      printf "\r  ${CYN}%s${R}  %s" "${frames:i++%${#frames}:1}" "$msg"
      sleep 0.1
    done
    printf "\r\033[K"
  fi
  if wait "$pid"; then
    ok "$msg"
  else
    fail "$msg"
    echo -e "     ${GRY}Lihat log: ${LOG_FILE}${R}" >&2
    echo -e "${GRY}$(tail -n 8 "$LOG_FILE")${R}" >&2
    exit 1
  fi
}

on_error() {
  local line="$1" cmd="$2"
  fail "Instalasi gagal pada baris ${line}"
  echo -e "     ${GRY}Perintah : ${cmd}${R}" >&2
  echo -e "     ${GRY}Log      : ${LOG_FILE}${R}" >&2
  echo "[ERROR] baris ${line}: ${cmd}" >>"$LOG_FILE" 2>/dev/null || true
}
trap 'on_error "$LINENO" "$BASH_COMMAND"' ERR

# ---------------------------------------------------------------------------
# Pra-pemeriksaan
# ---------------------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}${B}[!] Script ini harus dijalankan sebagai root.${R}"
  echo -e "    Gunakan: ${B}sudo bash $0${R}"
  exit 1
fi

mkdir -p "$(dirname "$LOG_FILE")"
: > "$LOG_FILE"

banner

# ---------------------------------------------------------------------------
# Cek tools yang sudah terpasang
# ---------------------------------------------------------------------------
TOOLS=(nuclei subfinder httpx)
MISSING=()
for t in "${TOOLS[@]}"; do
  command -v "$t" >/dev/null 2>&1 || MISSING+=("$t")
done

if [[ ${#MISSING[@]} -eq 0 ]]; then
  echo -e "  ${GRN}${B}✔ Semua tools sudah terpasang. Instalasi dihentikan.${R}\n"
  printf "  ${B}%-12s %-26s %s${R}\n" "TOOL" "LOKASI" "VERSI"
  printf "  ${GRY}%s${R}\n" "────────────────────────────────────────────────────"
  for t in "${TOOLS[@]}"; do
    ver=$("$t" -version 2>&1 | grep -Eo 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)
    printf "  ${GRN}%-12s${R} %-26s %s\n" "$t" "$(command -v "$t")" "${ver:--}"
  done
  echo
  echo -e "  ${D}Untuk memperbarui, hapus binary lama lalu jalankan ulang skrip ini.${R}"
  echo -e "  ${D}Crafted by ${AUTHOR}${R}\n"
  exit 0
fi

warn "Belum terpasang: ${MISSING[*]}"

# ---------------------------------------------------------------------------
# 1. Sistem
# ---------------------------------------------------------------------------
step "Memeriksa sistem"
ARCH=$(dpkg --print-architecture 2>/dev/null || true)
if [[ -z "$ARCH" ]]; then
  case "$(uname -m)" in
    x86_64)        ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *)             ARCH="$(uname -m)" ;;
  esac
fi
OS_NAME=$(grep -m1 '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2- | tr -d '"' || true)
OS_NAME="${OS_NAME:-Linux}"
info "OS          : ${OS_NAME}"
info "Arsitektur  : ${ARCH}"
info "Pengguna    : $(id -un 2>/dev/null || echo root)"

# ---------------------------------------------------------------------------
# 2. Dependensi
# ---------------------------------------------------------------------------
step "Memasang dependensi"
export DEBIAN_FRONTEND=noninteractive
run "Memperbarui indeks paket (apt update)" apt-get update -y
run "Memasang golang-go, git, curl, wget"   apt-get install -y golang-go git curl wget ca-certificates

# ---------------------------------------------------------------------------
# 3. Go
# ---------------------------------------------------------------------------
step "Memverifikasi Go (minimal 1.${MIN_GO_MINOR})"
go_minor() { go version | sed -E 's/.*go1\.([0-9]+).*/\1/'; }

if ! command -v go >/dev/null 2>&1 || [[ "$(go_minor)" -lt $MIN_GO_MINOR ]]; then
  warn "Go dari apt terlalu lama, memasang Go terbaru dari go.dev"
  GO_VER=$(curl -fsSL "https://go.dev/VERSION?m=text" | head -n1)
  run "Mengunduh ${GO_VER}" curl -fsSL "https://go.dev/dl/${GO_VER}.linux-${ARCH}.tar.gz" -o /tmp/go.tar.gz
  rm -rf /usr/local/go
  run "Mengekstrak ke /usr/local/go" tar -C /usr/local -xzf /tmp/go.tar.gz
  rm -f /tmp/go.tar.gz
  export PATH=/usr/local/go/bin:$PATH
  ln -sf /usr/local/go/bin/go    /usr/bin/go
  ln -sf /usr/local/go/bin/gofmt /usr/bin/gofmt
fi
ok "$(go version)"

export GOPATH="${GOPATH:-/root/go}"
export GOBIN="$GOPATH/bin"
mkdir -p "$GOBIN"

# ---------------------------------------------------------------------------
# 4. Instalasi tools
# ---------------------------------------------------------------------------
step "Memasang tools ProjectDiscovery"
install_tool() {
  local name="$1" pkg="$2"
  if command -v "$name" >/dev/null 2>&1; then
    ok "${name} sudah terpasang, dilewati"
    return 0
  fi
  run "Compile & install ${B}${name}${R} (bisa beberapa menit)" go install "${pkg}@latest"
  cp -f "$GOBIN/$name" /usr/bin/
  chmod +x "/usr/bin/$name"
}

install_tool nuclei    github.com/projectdiscovery/nuclei/v3/cmd/nuclei
install_tool subfinder github.com/projectdiscovery/subfinder/v2/cmd/subfinder
install_tool httpx     github.com/projectdiscovery/httpx/cmd/httpx

# ---------------------------------------------------------------------------
# 5. Template Nuclei
# ---------------------------------------------------------------------------
step "Memperbarui template Nuclei"
if nuclei -update-templates >>"$LOG_FILE" 2>&1; then
  ok "Template Nuclei diperbarui"
else
  warn "Update template gagal (non-fatal). Jalankan manual: nuclei -update-templates"
fi

# ---------------------------------------------------------------------------
# 6. Verifikasi
# ---------------------------------------------------------------------------
step "Verifikasi instalasi"
printf "\n  ${B}%-12s %-26s %s${R}\n" "TOOL" "LOKASI" "STATUS"
printf "  ${GRY}%s${R}\n" "────────────────────────────────────────────────────"
for t in nuclei subfinder httpx; do
  if path=$(command -v "$t" 2>/dev/null); then
    printf "  ${GRN}%-12s${R} %-26s ${GRN}✔ terpasang${R}\n" "$t" "$path"
  else
    printf "  ${RED}%-12s${R} %-26s ${RED}✘ tidak ditemukan${R}\n" "$t" "-"
  fi
done

# ---------------------------------------------------------------------------
# Ringkasan
# ---------------------------------------------------------------------------
ELAPSED=$(( $(date +%s) - START_TS ))
echo
echo -e "  ${GRY}────────────────────────────────────────────────────────${R}"
echo -e "  ${GRN}${B}✔ INSTALASI SELESAI${R}  ${D}(${ELAPSED} detik)${R}"
echo -e "  ${GRY}────────────────────────────────────────────────────────${R}"
echo -e "  ${B}Contoh penggunaan:${R}"
echo -e "    ${CYN}subfinder${R} -d example.com -silent | ${CYN}httpx${R} -silent | ${CYN}nuclei${R} -severity high,critical"
echo
echo -e "  ${YLW}⚠ Gunakan hanya pada target yang Anda miliki izin resmi untuk diuji.${R}"
echo -e "  ${D}Crafted by ${AUTHOR} • Stay curious, stay ethical.${R}"
echos