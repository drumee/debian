#!/bin/bash
source /etc/drumee/drumee.sh
base_dir=$DRUMEE_LOG_DIR
cd "$base_dir" || exit 1
rotate_file() {
  local file=$1 i=$2
  if [ -f "$file.$i" ]; then
    if [ -f "$file.$((i + 1))" ]; then
      mv "$file.$((i + 1))" "$file.$((i + 2))"
    fi
    mv "$file.$i" "$file.$((i + 1))"
  fi
}
for file in "$base_dir/"*.log; do
  [ -f "$file" ] || continue
  for i in 7 6 5 4 3 2 1; do
    rotate_file "$file" "$i"
  done
  cp "$file" "$file.1"
  chown "$DRUMEE_SYSTEM_USER:$DRUMEE_SYSTEM_USER" "$file.1"
  : > "$file"
done
exit 0
