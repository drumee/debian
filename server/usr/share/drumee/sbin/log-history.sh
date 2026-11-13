#!/bin/bash
source /etc/drumee/drumee.sh
base_dir=$DRUMEE_LOG_DIR
cd "$base_dir" || exit 1

dest=$(date +"%Y-%m-%d")
mkdir -p "$dest"
for file in *.log; do
  [ -f "$file" ] || continue
  cp "$file" "$dest/$file"
  chown "$DRUMEE_SYSTEM_USER:$DRUMEE_SYSTEM_USER" "$dest/$file"
  : > "$file"
done
exit 0
