#!/usr/bin/env bash
# pull_router_backups.sh
# Host-side pull of RouterOS backup files created by backup.lua (names
# backup-*.{backup,rsc}) over SSH/SCP. Enable SSH + SFTP on the router
# (IP → Services), use a key-based user with sufficient rights.
#
# Usage:
#   ./pull_router_backups.sh user@router-host [dest-dir]
#
# Example:
#   ./pull_router_backups.sh admin@192.168.88.1 ~/Archive/mikrotik-backups
#
# Wildcard SCP requires RouterOS 7+ SFTP. If a pattern fails, re-run after
# backups exist or copy explicit filenames.

set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'EOF'
Usage: pull_router_backups.sh user@router-host [dest-dir]

Pull backup-*.backup and backup-*.rsc from a RouterOS 7+ router over SFTP/SCP.
dest-dir defaults to ./router-backups. Expects non-interactive SSH (keys).

Example:
  pull_router_backups.sh admin@192.168.88.1 ~/Archive/mikrotik-backups
EOF
  exit 0
fi

R="${1:?usage: $0 user@router-host [dest-dir]}"
D="${2:-./router-backups}"

mkdir -p "$D"

SCP_OPTS=( -o BatchMode=yes -o StrictHostKeyChecking=accept-new )

shopt -s nullglob
got=0
for ext in backup rsc; do
  if scp "${SCP_OPTS[@]}" -p "$R:backup-*.$ext" "$D/" 2>/dev/null; then
    got=1
  fi
done
shopt -u nullglob

if (( got )); then
  echo "Pulled backup-* files into $D"
else
  echo "No backup-*.backup / backup-*.rsc matched on $R — nothing pulled (exit 0)." >&2
fi
