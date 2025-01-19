#!/usr/bin/env sh
set -e
echo "args: $@"
echo "FOO: $FOO"
printf 1 >> count.txt
count=$(wc -c < count.txt)
echo "count: ${count}"
if [ "$count" -le 5 ]; then
    exit 1
fi
rm count.txt
