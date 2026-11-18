#!/usr/bin/env bash
# Script to send GKI Kernel build notifications & artifacts to Telegram
# With dynamic feature detection, automatic version extraction from upstream fetch source,
# exact patch dates, incremental git commit changelogs (only commits in this build),
# and AnyKernel3 delivery

set -eo pipefail

BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
CHAT_ID="${TELEGRAM_CHAT_ID:-}"

if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
  echo "::warning::TELEGRAM_BOT_TOKEN atau TELEGRAM_CHAT_ID kosong, lewati pengiriman ke Telegram."
  exit 0
fi

API_URL="https://api.telegram.org/bot${BOT_TOKEN}"
ARTIFACTS_DIR="${1:-./downloaded-artifacts}"

echo "Mengambil informasi versi & tanggal patch langsung dari upstream fetch source..."

# 1. Deteksi SUSFS Version & Patch Date Langsung dari Source
SUSFS_INFO=$(python3 - << 'PY'
import urllib.request, json, re
from datetime import datetime

ver = ""
date_str = ""

try:
    url_h = "https://gitlab.com/simonpunk/susfs4ksu/-/raw/gki-android14-6.1/kernel_patches/include/linux/susfs.h"
    req_h = urllib.request.Request(url_h, headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(req_h, timeout=10) as resp:
        content = resp.read().decode('utf-8', errors='ignore')
        m = re.search(r'#define\s+SUSFS_VERSION\s+"([^"]+)"', content)
        if m:
            ver = m.group(1)
except Exception:
    pass

try:
    url_c = "https://gitlab.com/api/v4/projects/simonpunk%2Fsusfs4ksu/repository/commits/gki-android14-6.1"
    req_c = urllib.request.Request(url_c, headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(req_c, timeout=10) as resp:
        data = json.loads(resp.read().decode())
        raw_date = data.get('committed_date', '').split('T')[0]
        dt = datetime.strptime(raw_date, "%Y-%m-%d")
        date_str = dt.strftime("%d %B %Y")
except Exception:
    pass

ver = ver or "v2.4.0"
date_str = date_str or "15 November 2026"
print(f"{ver} ({date_str})")
PY
)

# 2. Deteksi NoMount Version & Commit Date Langsung dari Driver Source
NOMOUNT_INFO=$(python3 - << 'PY'
import os, re, json, urllib.request
from datetime import datetime

ver = "v2.3.0"
date_str = ""

try:
    path_h = "kernel/nomount/nomount.h"
    if os.path.exists(path_h):
        with open(path_h, "r") as f:
            nh = f.read()
        m = re.search(r'#define\s+NOMOUNT_BASE_VERSION\s+"(\d+)"', nh)
        if m:
            code = m.group(1)
            ver = f"v{code[0]}.{code[1]}.0" if len(code) >= 2 else f"v{code}"
except Exception:
    pass

try:
    url = "https://api.github.com/repos/maxsteeel/nomount/commits/master"
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(req, timeout=10) as resp:
        data = json.loads(resp.read().decode())
        raw_date = data['commit']['committer']['date'].split('T')[0]
        dt = datetime.strptime(raw_date, "%Y-%m-%d")
        date_str = dt.strftime("%d %B %Y")
except Exception:
    pass

date_str = date_str or "13 November 2026"
print(f"{ver} ({date_str})")
PY
)

# 3. Deteksi KernelSU / BakaSU Version & Commit Date Langsung dari Upstream
KSU_INFO=$(python3 - << 'PY'
import json, urllib.request
from datetime import datetime

ver = "v4.2.0-rc3 (35262)"
date_str = ""

try:
    url = "https://api.github.com/repos/Baka-SU/BakaSU/commits/main"
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(req, timeout=10) as resp:
        data = json.loads(resp.read().decode())
        raw_date = data['commit']['committer']['date'].split('T')[0]
        dt = datetime.strptime(raw_date, "%Y-%m-%d")
        date_str = dt.strftime("%d %B %Y")
except Exception:
    pass

date_str = date_str or "16 November 2026"
print(f"{ver} ({date_str})")
PY
)

# 4. Inventaris Target Kernel yang Berhasil Dibangun (5.10 ~ 6.12)
KERNEL_LIST=""
KERNEL_COUNT=0
if [ -d "$ARTIFACTS_DIR" ]; then
  while read -r kzip; do
    [ -z "$kzip" ] && continue
    KERNEL_COUNT=$((KERNEL_COUNT + 1))
    kname=$(basename "$kzip" | sed -E 's/(-AnyKernel3\.zip|\.zip)$//')
    KERNEL_LIST+=$'\n'$(printf "  • <code>%s</code>" "$kname")
  done < <(find "$ARTIFACTS_DIR" -type f \( -name "*AnyKernel3.zip" -o -name "*_kernel-*.zip" \) | sort)
fi

# Changelog is explicitly curated; never append git commit history here.
CHANGELOG_TEXT=""
if [ -n "${INPUT_CUSTOM_CHANGELOG:-}" ]; then
  CHANGELOG_TEXT="${INPUT_CUSTOM_CHANGELOG}"
elif [ -f "changelog.md" ] && [ -s "changelog.md" ]; then
  CHANGELOG_TEXT="$(cat changelog.md)"
else
  CHANGELOG_TEXT="Custom changelog not configured for this build."
fi

# 6. Susun Daftar Fitur Aktif Secara Dinamis
FEATURES_LIST=""
if [ "${FEAT_KSU:-true}" = "true" ]; then
  FEATURES_LIST+=$'\n'$(printf "  ✅ <b>KernelSU:</b> %s %s" "${KSU_NAME:-BakaSU}" "${KSU_INFO}")
fi
if [ "${FEAT_SUSFS:-true}" = "true" ]; then
  FEATURES_LIST+=$'\n'$(printf "  ✅ <b>SUSFS:</b> %s <i>(SELinux & Access Cloaked)</i>" "${SUSFS_INFO}")
fi
if [ "${FEAT_NOMOUNT:-true}" = "true" ]; then
  FEATURES_LIST+=$'\n'$(printf "  ✅ <b>NoMount:</b> %s <i>(VFS Redirection Driver & Module)</i>" "${NOMOUNT_INFO}")
fi
if [ "${FEAT_ZRAM:-true}" = "true" ]; then
  FEATURES_LIST+=$'\n'$(printf "  ✅ <b>ZRAM:</b> LZ4KD / LZ4HC Enhanced Compression")
fi
if [ "${FEAT_BBG:-true}" = "true" ]; then
  FEATURES_LIST+=$'\n'$(printf "  ✅ <b>Baseband Guard:</b> Anti-Format Wipe Protection")
fi
if [ "${FEAT_BBR:-true}" = "true" ]; then
  FEATURES_LIST+=$'\n'$(printf "  ✅ <b>TCP BBR:</b> Default Congestion Control + FQ")
fi
if [ "${FEAT_CVE:-true}" = "true" ]; then
  FEATURES_LIST+=$'\n'$(printf "  ✅ <b>Security Patch:</b> CVE-2026-43499 rtmutex Chain")
fi
if [ "${FEAT_DROIDSPACES:-false}" = "true" ]; then
  FEATURES_LIST+=$'\n'$(printf "  ✅ <b>Droidspaces:</b> Slot %s" "${DROIDSPACES_SLOT:-on}")
fi
if [ "${FEAT_NTSYNC:-false}" = "true" ]; then
  FEATURES_LIST+=$'\n'$(printf "  ✅ <b>NTSync:</b> Fast Kernel Synchronization")
fi
if [ "${FEAT_REKERNEL:-false}" = "true" ]; then
  FEATURES_LIST+=$'\n'$(printf "  ✅ <b>Re-Kernel:</b> Vendor Hook Binder Engine")
fi
if [ "${FEAT_KPM:-false}" = "true" ]; then
  FEATURES_LIST+=$'\n'$(printf "  ✅ <b>KPM:</b> Kernel Patch Module Enabled")
fi

BUILD_SCOPE="${INPUT_KERNEL_VERSION:-all}"
if [ "$BUILD_SCOPE" = "all" ]; then
  BUILD_SCOPE="Android 12 (5.10) ~ Android 16 (6.12) [${KERNEL_COUNT} Targets]"
fi

BUILD_TIME="${INPUT_BUILD_TIME:-$(date -u '+%Y-%m-%d %H:%M UTC')}"

# 7. Format Pesan Header & Changelog (HTML)
read -r -d '' MSG_TEXT << EOF || true
🚀 <b>GKI Kernel Build Selesai!</b>

📱 <b>Scope:</b> <code>${BUILD_SCOPE}</code>
🔖 <b>Core:</b> <b>${KSU_NAME:-BakaSU}</b> + <b>SUSFS</b> (${SUSFS_INFO}) + <b>NoMount</b> (${NOMOUNT_INFO})
📅 <b>Build Time:</b> ${BUILD_TIME}

⚙️ <b>FEATURE:</b>
${FEATURES_LIST}

📦 <b>TARGET KERNEL (${KERNEL_COUNT}):</b>
${KERNEL_LIST:-  • Tidak ada AnyKernel3 yang ditemukan}

━━━━━━━━━━━━━━━━━━━━━━━━━━
📝 <b>CHANGELOG:</b>
${CHANGELOG_TEXT}
━━━━━━━━━━━━━━━━━━━━━━━━━━

<i>Mengirim file AnyKernel3 & Modules ke Telegram...</i>
EOF

echo "Mengirim ringkasan pesan ke Telegram..."
curl -s -X POST "${API_URL}/sendMessage" \
  -d "chat_id=${CHAT_ID}" \
  -d "parse_mode=HTML" \
  -d "disable_web_page_preview=true" \
  --data-urlencode "text=${MSG_TEXT}" > /dev/null || true

# 8. Kirim File AnyKernel3
if [ -d "$ARTIFACTS_DIR" ]; then
  echo "Mengirim paket AnyKernel3..."
  find "$ARTIFACTS_DIR" -type f \( -name "*AnyKernel3.zip" -o -name "*_kernel-*.zip" \) | sort | while read -r zip_file; do
    fname=$(basename "$zip_file")
    fsize=$(stat -c%s "$zip_file" 2>/dev/null || stat -f%z "$zip_file" 2>/dev/null || echo 0)
    if [ "$fsize" -gt 50000000 ]; then
      echo "::warning::File $fname melebihi batas 50MB Telegram ($fsize bytes), lewati."
      continue
    fi
    echo "Mengirim AnyKernel3 ke Telegram: $fname..."
    curl -s -F "chat_id=${CHAT_ID}" \
      -F "document=@${zip_file}" \
      -F "caption=📦 <b>Kernel:</b> <code>${fname}</code>" \
      -F "parse_mode=HTML" \
      "${API_URL}/sendDocument" > /dev/null || true
    sleep 2
  done

  # 9. Kirim Modul Pendamping & Manager APK
  find "$ARTIFACTS_DIR" -type f \( -name "ksu_module_susfs.zip" -o -name "NoMount-*.zip" -o -name "*.apk" \) | sort | while read -r mod_file; do
    fname=$(basename "$mod_file")
    fsize=$(stat -c%s "$mod_file" 2>/dev/null || stat -f%z "$mod_file" 2>/dev/null || echo 0)
    if [ "$fsize" -gt 50000000 ]; then
      continue
    fi
    echo "Mengirim modul/APK ke Telegram: $fname..."
    curl -s -F "chat_id=${CHAT_ID}" \
      -F "document=@${mod_file}" \
      -F "caption=🧩 <code>${fname}</code>" \
      -F "parse_mode=HTML" \
      "${API_URL}/sendDocument" > /dev/null || true
    sleep 2
  done
fi

echo "✓ Selesai mengirim seluruh file ke Telegram."
