#!/usr/bin/env bash

# Utilities Lib for various things used across scripts in the repo

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

# Remove Escape sequences from nickel code generated as a string from nickel itself
# $1 string
# $2 file_path
raw_string() {
	str=$1
	str="${str:1:-1}"
	str="${str//\\n/$'\n'}"
	str="${str//\\\"/\"}"
	echo "$str" >"$2"

	# TODO: do we need these?
	# sed 's/m%\\"/m%"/g' "$2" -i
	# sed 's/\\"\\%/"%/g' "$2" -i
	# sed 's/\\"/"/g' "$2" -i
}
