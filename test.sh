#!/usr/bin/env bash

: '
    This is the tester for for the schema generation.
    All tests lives in ./tests/schemas/* and each directory can contain many tests
    Each test repo should have the following;
    - test.ncl: test cases against the generated contract
    - schema.json: the schema used when generating the test contract
    - contract.ncl: the generated contract which should be used in test.ncl
'

set -e -o pipefail

generate_and_run_tests() {

	# base case when we are passing a file
	if [ ! -d "$1" ]; then
		return 0
	fi

	# shellcheck disable=SC2231
	for dir in $1/*; do

		if [ -f "$dir/schema.json" ]; then
			# generate the contract used in test
			GENERATED_FILE_NAME="${dir}/contract.ncl"
			echo "Generating contract at $GENERATED_FILE_NAME"
			nickel export -f raw tester.ncl -I "${dir}" | nickel format >"$GENERATED_FILE_NAME"

			# format and run the test
			TESTFILE="$dir/test.ncl"
			echo "Running test $TESTFILE"
			nickel format "$GENERATED_FILE_NAME"
			nickel eval "$TESTFILE" -I "${PWD}" >/dev/null
		fi

		# recurse into each sub-directory
		generate_and_run_tests "$dir"
	done
}

generate_and_run_tests "./tests/schemas"
