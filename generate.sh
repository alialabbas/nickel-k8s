#!/usr/bin/env bash

: '
    Fetch and Generate k8s contracts from their source swagger.json file.
    This fetches is the list of tags using GitHub API and then download swagger.json into a k8s/version/swagger.json
    Versions are filtered based on what is deemed to be the minimal accepted version
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
GENERATED_FILE_NAME=k8s.ncl

i=1
result=$(curl -s "https://api.github.com/repos/kubernetes/kubernetes/tags?per_page=100&page=$i" | jq -r .[]?.name)

while [[ $result != "" ]]; do
	result=$(echo "$result" | grep '^v[0-9]*.[0-9]*.[0-9]*$' | sort --version-sort | sed -n '/v1.30.0/,$p')

	for version in $result; do

		echo -e "${GREEN}Generate Contracts for kube version ${version}${NC}"
		dir="./k8s/$version"
		mkdir -p "$dir"

		curl --silent --output "$dir/swagger.json" "https://raw.githubusercontent.com/kubernetes/kubernetes/$version/api/openapi-spec/swagger.json"

		file_path="$dir/$GENERATED_FILE_NAME"

		log_info "Generating"
		result=$(nickel eval -I "$dir" ./generated-k8s.ncl 2>./errs)

		log_info "Escaping code"
		raw_string "$result" "$file_path"

		log_info "Formatting"
		nickel format "$file_path"

	done

	i=$((i + 1))
	result=$(curl -s "https://api.github.com/repos/kubernetes/kubernetes/tags?per_page=100&page=$i" | jq -r .[]?.name)

done
