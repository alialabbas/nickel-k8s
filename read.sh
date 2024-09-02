#!/usr/bin/env bash
input="/path/to/txt/file"
######################################
# $IFS removed to allow the trimming #
#####################################
while IFS=$'\\n' read -r line; do
	## take some action on $line
	printf "%b" "$line"
done < <(nickel eval -I ./tests/schemas/string/regex ./tester.ncl)

