#!/usr/bin/env bash
# Export the Web build and upload it to the team server, where Caddy serves it
# behind Cloudflare at https://back2earth.pp.ua. Owner: D (release).
# Pushing to main does this automatically (.github/workflows/deploy-web.yml);
# this script is for deploying by hand.
#
#   GODOT=/path/to/Godot_v4.7.2-stable_console.exe tools/deploy_web.sh
#
# Needs: the pinned Godot with its export templates, and SSH access to the
# server. Server address and key path come from .env (gitignored; copy
# .env.example). The server setup itself (Caddy, firewall, companion service)
# is described in README "Hosting".
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -f .env ]; then
  set -a; . ./.env; set +a
fi
: "${DEPLOY_SERVER:?Set DEPLOY_SERVER in .env (see .env.example)}"
: "${DEPLOY_SSH_KEY:?Set DEPLOY_SSH_KEY in .env (see .env.example)}"

GODOT="${GODOT:-godot}"
SSH_KEY="${DEPLOY_SSH_KEY/#\~/$HOME}"
SERVER="$DEPLOY_SERVER"
OUT=build/web

rm -rf "$OUT"
mkdir -p "$OUT"
"$GODOT" --headless --path . --export-release "Web" "$OUT/index.html"
cp web/favicon.ico "$OUT/favicon.ico"   # pixel-art Earth (tools/make_logo.py)
# The ~40 MB wasm shrinks to ~10 MB; Caddy serves the .gz to browsers that accept it.
gzip -9 -k -f "$OUT/index.wasm"
ls -l "$OUT"

# Unpack into a fresh folder, then swap it in, so visitors never see half a build.
tar -C "$OUT" -czf - . | ssh -i "$SSH_KEY" "$SERVER" '
  set -e
  sudo rm -rf /var/www/back2earth.new
  sudo install -d -m 755 /var/www/back2earth.new
  sudo tar -xzf - -C /var/www/back2earth.new --no-same-owner
  sudo rm -rf /var/www/back2earth.old
  [ -d /var/www/back2earth ] && sudo mv /var/www/back2earth /var/www/back2earth.old
  sudo mv /var/www/back2earth.new /var/www/back2earth
  ls -l /var/www/back2earth'

echo "Deployed. Cloudflare may cache old files for a few minutes; purge the cache if needed."
