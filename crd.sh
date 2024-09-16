#!/usr/bin/env bash

: '
    Processes crd-catalog.yaml and fetch each manifest from source
    All manifest will be stored in crds/ and processed by the generator
'

set -e -o pipefail

source ./lib.sh

# system check
check "nickel"
check "curl"
check "sed"
check "jq"

# clean up
trap "[ -f ./errs ] && cat ./errs && rm ./errs >/dev/null 2>&1" ERR
trap "rm ./errs >/dev/null 2>&1" 0

# business logic

while read -r crd; do
	owner=$(jq -r .owner <<<"$crd")
	repo=$(jq -r .repo <<<"$crd")
	rev=$(jq -r .rev <<<"$crd")
	path=$(jq -r .path <<<"$crd")
	url=$(jq -r .url <<<"$crd")

	dir="./crds/$repo"

	mkdir -p "$dir"

	log_info "Downloading crd for $repo"
	if [ "$url" != "null" ]; then
		# TODO: url could just be the uri path to the github repo and then the rest comes from here
		curl --silent -L "$url" -H "Accept: application/octet-stream" --output "$dir/crd.yaml"
	else
		curl --silent --output "$dir/crd.yaml" "https://raw.githubusercontent.com/$owner/$repo/$rev/$path"
	fi

	log_info "Generationg contract for $repo"
	file_path="$dir/crd.ncl"

	result=$(nickel eval -I "$dir" ./crds.ncl 2>./errs)
	echo "${result:1:-1}" >"$file_path"

	# Fix string formatting since nickel will always escape " and no other way to print this for now
	sed 's/\\n/\n/g' "$file_path" -i
	sed 's/m%\\"/m%"/g' "$file_path" -i
	sed 's/\\"\\%/"%/g' "$file_path" -i
	sed 's/\\"/"/g' "$file_path" -i

	nickel format "$file_path"

done < <(jq -c '.[]' ./crd-catalog.json)
