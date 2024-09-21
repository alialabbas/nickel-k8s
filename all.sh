#!/usr/bin/env bash

result="{"
for dir in ./k8s/*; do
    version="$(basename "$dir")"
    result="$result\n\"$version\" = import \"k8s/$version/k8s.ncl\","
done

result="$result}"
echo -e "$result" > all.ncl
