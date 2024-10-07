#!/usr/bin/env bash

set -e -o pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
	echo -e "$GREEN$1$NC"
}

log_err() {
	echo -e "$RED$1$NC"
}

# Check if a binary exist in the system path
check() {
	if ! command -v "$1" >/dev/null 2>&1; then
		echo -e "${RED}You don't have $BLUE\`${1}\`$RED installed to run this script${NC}"
		exit 1
	fi
}

# system check
check "nickel"
check "curl"
check "sed"
check "jq"

file="$1"

cache=~/.nickel-k8s
mkdir -p ~/.nickel-k8s/{crds,k8s}

# This is necessary to do because we have a module that has a static import and need to have the value defined in advance.
echo "{}" >"$cache/k8s.ncl"
echo "{}" >"$cache/merged-k8s.ncl"
echo "{}" >"$cache/crds.ncl"

k8s_version="$(nickel export -f raw -I ./ -I $cache "$file" --field k8s_version)"
crds="$(nickel export -f json -I ./ -I $cache "$file" --field crds)"

rm "$cache/k8s.ncl"
rm "$cache/merged-k8s.ncl"
rm "$cache/crds.ncl"

mkdir -p ~/.nickel-k8s/k8s/"$k8s_version"

curl --silent -L "https://raw.githubusercontent.com/kubernetes/kubernetes/$k8s_version/api/openapi-spec/swagger.json" >"$cache/k8s/$k8s_version/schema.json"
if [ ! -f "$cache/k8s/$k8s_version/k8s.ncl" ]; then
	nickel export -f raw generated-k8s.ncl --field Output -- Input="(import \"$cache/k8s/$k8s_version/schema.json\")" | nickel format >"$cache/k8s/$k8s_version/k8s.ncl"
fi

if [ ! -f "$cache/k8s/$k8s_version/merged-k8s.ncl" ]; then
	nickel export -f raw merge.ncl --field Output -- Input="(import \"$cache/k8s/$k8s_version/schema.json\")" >"$cache/k8s/$k8s_version/merged-k8s.ncl"
fi

result=""
while read -r crd; do
	url=$(jq -r .url <<<"$crd")
	version=$(jq -r .version <<<"$crd")
	name=$(jq -r .name <<<"$crd")
	mkdir -p "$cache/crds/$name/$version"
	curl --silent -L "$url" >"$cache/crds/$name/$version/crd.yaml"

	if [ ! -f "$cache/crds/$name/$version/crd.ncl" ]; then
		nickel export -f raw ./generated-crds.ncl --field Output -- Input="(import \"$cache/crds/$name/$version/crd.yaml\")" | nickel format >"$cache/crds/$name/$version/crd.ncl"
	fi

	# build up a single crd.yaml file that will be used to link all generated contracts into a single file
	# This is always regenerated since the user might just remove or add existing crds and need to be regenerated
	if [ -z "${result}" ]; then
		result="(import \"$cache/crds/$name/$version/crd.ncl\")"
	else
		result="$result & (import \"$cache/crds/$name/$version/crd.ncl\")"
	fi
done < <(echo "$crds" | jq -c -r '.[]')

if [ -z "${result}" ]; then
	# we still need an empty crds list from the cache to load the module correctly
	echo "{}" >"$cache/crds/crds.ncl"
else
	echo "$result" | nickel format >"$cache/crds/crds.ncl"
fi

nickel export -I ./ -I "$cache/crds" -I "$cache/k8s/$k8s_version" -f yaml "$file" --field Package
