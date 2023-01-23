#!/usr/bin/env bash

function maybe_skip() {
	OLD_PWD=$(pwd)
	if [ ! -d "${GITHUB_WORKSPACE}/remote-ignore" ]; then
		mkdir -p "${GITHUB_WORKSPACE}/remote-ignore"
		cd "${GITHUB_WORKSPACE}/remote-ignore"
		git init
		git checkout --orphan orphan_name
		echo "$INPUT_FORCE_IGNORE" > ".gitignore"
	fi
	pwd 
	ls -al "${GITHUB_WORKSPACE}/remote-ignore"
	git --work-tree="${GITHUB_WORKSPACE}/remote-ignore" check-ignore -q --no-index "$1"
	status=$?
	cd "$OLD_PWD"
	if [ $status -eq 1 ]; then
		return 0;
	else
		return 1;
	fi
}

function process_line() {
	line="$1"
	operation="${line::1}"
	file="${line:2}"
	maybe_skip "$file"
	ret="$?"
	if [ "$ret" -eq 1 ]; then
		echo "skipping $file"
		return 0;
	fi
	local_remote_file="${GITHUB_WORKSPACE}/remote/${file}"
	local_file="${INPUT_ENV_LOCAL_ROOT}/${file}"
	if [ "${operation}" == "*" ]; then
		if [ ! -d "${local_remote_file}" ]; then
			echo "mkdir -p '${local_remote_file}'"
			mkdir -p "${local_remote_file}" || return 1
		fi
	elif [ "${operation}" == "+" ]; then
		echo "cp -f '${local_file}' '${local_remote_file}'"
		cp -f "${local_file}" "${local_remote_file}" || return 1
	elif [ "${operation}" == "-" ]; then
		echo "rm -f '${local_remote_file}'"
		rm -f "${local_remote_file}" || return 1
	elif [ "${operation}" == "_" ]; then
		if [ -z "$(ls -A "$local_remote_file")" ]; then
			echo "rm -rf '${local_remote_file}'"
			rm -rf "${local_remote_file}" || return 1
		fi
	fi
}

function handle_sigchld() {
    for PID in "${!PIDS[@]}"; do
        if [ ! -d "/proc/$PID" ]; then
            wait "$PID"
            CODE=$?
			if [ $CODE -ne 0 ]; then
				exit "$CODE"
			fi
            unset "PIDS[$PID]"
        fi
    done
}

JOBS_LIMIT=${INPUT_CONCURRENT_CONNECTIONS}
PIDS=()
trap handle_sigchld SIGCHLD

function spawn_process_line() {
	while [ "$(jobs -rp | wc -l)" -ge $JOBS_LIMIT ]; do
        sleep 1
    done
	line="$1"
	process_line "$line" &
	PIDS[$!]=1
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
		while [ "$path" != '.' ]; do
			pathsToCreate[$path]=0
			path="$(dirname "${path}")"
		done
		uploads[$file]=0
	elif [ "${operation}" == "-" ]; then
		while [ "$path" != '.' ]; do
			pathsToCleanup[$path]=0
			path="$(dirname "${path}")"
		done
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
