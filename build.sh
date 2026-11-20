#!/usr/bin/env bash
# Sync the project's MQL5 sources into the (portable) MT5 MQL5 folder,
# compile one target, and print the compile log.
#
#   ./build.sh                                   # compiles the indicator
#   ./build.sh Experts/BBMA/BBMA_EA.mq5          # compiles a specific file
set -euo pipefail

PROJ="/run/media/xcode/DATA/coding/mql5/learn-mql5"
MT5="$HOME/.wine/drive_c/Program Files/HFM Metatrader 5"
MQL5="$MT5/MQL5"

TARGET="${1:-Indicators/BBMA/BBMA_OmaAlly.mq5}"

# copy sources into MT5 (merge, keep MT5's own files)
for d in Include Indicators Experts Scripts; do
  if [ -d "$PROJ/$d" ]; then
    mkdir -p "$MQL5/$d"
    cp -r "$PROJ/$d/." "$MQL5/$d/"
  fi
done

WINTARGET="MQL5\\${TARGET//\//\\}"
LOGWIN="MQL5\\compile.log"
LOGUNIX="$MQL5/compile.log"

cd "$MT5"
WINEDEBUG=-all wine MetaEditor64.exe /portable /compile:"$WINTARGET" /log:"$LOGWIN" || true

echo "----- compile log: $TARGET -----"
iconv -f utf-16 -t utf-8 "$LOGUNIX" 2>/dev/null || cat "$LOGUNIX"
