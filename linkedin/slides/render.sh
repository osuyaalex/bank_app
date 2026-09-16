#!/bin/zsh
# Re-render slides. ./render.sh            -> all
#                  ./render.sh s1 p2b      -> just those
cd "${0:A:h}"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
names=(${@:-s1 s2 s3 p2a p2b p2c p3a p3b p3c})
for n in $names; do
  case $n in
    s1) out=part1-1 ;; s2) out=part1-2 ;; s3) out=part1-3 ;;
    p2a) out=part2-1 ;; p2b) out=part2-2 ;; p2c) out=part2-3 ;;
    p3a) out=part3-1 ;; p3b) out=part3-2 ;; p3c) out=part3-3 ;;
    *) out=$n ;;
  esac
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --allow-file-access-from-files \
    --screenshot="$HOME/Downloads/$out.png" --window-size=1080,1350 "file://$PWD/$n.html" 2>/dev/null
  echo "~/Downloads/$out.png"
done
