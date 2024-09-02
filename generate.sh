#!/usr/bin/env bash

set -e
GENERATED_FILE_NAME=generated.ncl
FILENAME=./generated-k8s.ncl

nickel eval $FILENAME | awk '{print substr($0, 2, length($0) - 2)}' > tmp.ncl

# shellcheck disable=SC2046
echo -e $(cat tmp.ncl) > $GENERATED_FILE_NAME

rm tmp.ncl

# Fix string formatting since nickel will always escape " and no other way to print this for now
sed 's/m%\\"/m%"/g' $GENERATED_FILE_NAME -i
sed 's/\\"\\%/"%/g' $GENERATED_FILE_NAME -i
sed 's/\\"/"/g' $GENERATED_FILE_NAME -i

# TODO: consider using alternative string to escape
# sed 's/\*\*REPLACEME\*\*/"%/g' $GENERATED_FILE_NAME -i

nickel format $GENERATED_FILE_NAME
