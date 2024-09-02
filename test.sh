#!/usr/bin/env bash

set -e

nickel_test() {
	dir=$(dirname "$1")
	GENERATED_FILE_NAME="${dir}/contract.ncl"
	echo "Generating contract at $GENERATED_FILE_NAME"
	nickel eval tester.ncl -I "${dir}" | awk '{print substr($0, 2, length($0) - 2)}' >"${GENERATED_FILE_NAME}"

	# Fix string formatting since nickel will always escape " and no other way to print this for now
	# TODO: use this instead of echo -e to make the file print new liens correctly
	# This will alllow us to keep the escaped data as is and only unescape what we want to truly unescape
	# This will become an issue when a doc string has \" in their doc string
	sed 's/\\n/\n/g' "$GENERATED_FILE_NAME" -i
	sed 's/m%\\"/m%"/g' "$GENERATED_FILE_NAME" -i
	sed 's/\\"\\%/"%/g' "$GENERATED_FILE_NAME" -i
	sed 's/\\"/"/g' "$GENERATED_FILE_NAME" -i

	TESTFILE="$dir/test.ncl"
	echo "Running test $TESTFILE"
	nickel format "$GENERATED_FILE_NAME"
	nickel eval "$TESTFILE" -I "${PWD}"
}

# TODO: need to exit on first failure or just aggregate all results somehow and return that
# TODO: need to figure out escape string hell here
export -f nickel_test
find ./tests -name schema.json -exec bash -c 'nickel_test $0' {} \;
