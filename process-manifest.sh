#!/usr/bin/env bash

function process_line() {
	line="$1"
	operation="${line::1}"
	file="${line:2}"
	local_remote_file="${GITHUB_WORKSPACE}/remote/${file}"
	local_file="${INPUT_ENV_LOCAL_ROOT}/${file}"
	if [ "${operation}" == "*" ]; then
		if [ ! -d "${local_remote_file}" ]; then
			echo "mkdir -p '${local_remote_file}'"
			mkdir -p "${local_remote_file}"
		fi
	elif [ "${operation}" == "+" ]; then
		echo "cp -f '${local_file}' '${local_remote_file}'"
		cp -f "${local_file}" "${local_remote_file}"
	elif [ "${operation}" == "-" ]; then
		echo "rm -f '${local_remote_file}'"
		rm -f "${local_remote_file}"
	elif [ "${operation}" == "_" ]; then
		if [ -z "$(ls -A "$local_remote_file")" ]; then
			echo "rm -rf '${local_remote_file}'"
			rm -rf "${local_remote_file}"
		fi
	fi
}

JOBS_LIMIT=5

function spawn_process_line() {
	while [ "$(jobs -rp | wc -l)" -ge $JOBS_LIMIT ]; do
        sleep 1
    done
	line="$1"
	process_line "$line" &
}

declare -A pathsToCreate
declare -A uploads
declare -A removals
declare -A pathsToCleanup

while read -r line; do
	if [ -z "${line}" ]; then
		continue;
	fi
	operation="${line::1}"
	file="${line:2}"
	path="$(dirname "${file}")"
	if [ "${operation}" == "+" ]; then
		if [ "$path" != '.' ]; then
			pathsToCreate[$path]=0
		fi
		uploads[$file]=0
	elif [ "${operation}" == "-" ]; then
		if [ "$path" != '.' ]; then
			pathsToCleanup[$path]=0
		fi
		removals[$file]=0
	fi
done < "${GITHUB_WORKSPACE}/file.manifest"

function sortPaths() {
	array=("$@")
	{
		for dir in "${array[@]}"; do
			depth=$(tr -dc '/' <<< "$dir" | awk '{ print length; }')
			if [ -z $depth ]; then
				depth=0
			fi
			printf "%s\t%s\n" "$depth" "$dir"
		done
	} | sort -k1,1r -k2,2 | cut -f2 -d$'\t'
}

mapfile -t orderedPathsToCreate < <(sortPaths "${!pathsToCreate[@]}")
mapfile -t orderedUploads < <(sortPaths "${!uploads[@]}")
mapfile -t orderedRemovals < <(sortPaths "${!removals[@]}")
mapfile -t orderedPathsToCleanup < <(sortPaths "${!pathsToCleanup[@]}")

for dir in "${orderedPathsToCreate[@]}"; do
	process_line "* ${dir}"
done
wait
echo "Finished preparing directory tree"

for file in "${orderedUploads[@]}"; do
	spawn_process_line "+ ${file}"
done
wait
echo "Finished uploads"

for file in "${orderedRemovals[@]}"; do
	spawn_process_line "- ${file}"
done
wait
echo "Finished removals"

for dir in "${orderedPathsToCleanup[@]}"; do
	process_line "_ ${dir}"
done
wait
echo "Finished cleanup of directory tree"
