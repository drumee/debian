#!/bin/bash
shopt -s extglob dotglob
base=$1
dest=$2
if [ -z $base ]; then 
  echo "Requires basedir" >&2
  exit 1;
fi
if [ -z $dest ]; then 
  echo "Requires destination" >&2
  exit 1;
fi
cd "$base" || exit 1;
# Debian 12+ ships 7-Zip in two shapes: the modern "7zip" package (binary 7zz on
# Debian 12, 7z on 13+) and the legacy p7zip wrapper (binary 7z). Prefer the
# modern binary, fall back to p7zip's 7z.
ZIP=$(command -v 7zz || command -v 7z)
[ -z "$ZIP" ] && { echo "No 7-Zip archiver (7zz/7z) found" >&2; exit 1; }
# The staging dir holds symlinks to the real files. p7zip stores symlinks AS
# links unless -l is given (the zip then carries broken alias stubs instead of
# file contents); modern 7-Zip follows symlinks by default and rejects -l. Pass
# -l only when the p7zip build is in use.
SL=""
$ZIP 2>&1 | grep -qi 'p7zip' && SL="-l"
nice $ZIP a -bsp1 -tzip $SL $dest.zip *