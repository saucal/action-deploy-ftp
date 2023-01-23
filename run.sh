#!/usr/bin/env bash

SECURE_PASS=$(echo "${INPUT_ENV_PASS}" | rclone obscure -)

mkdir -p "$HOME/.config/rclone"
{
	echo "[remote]"
	echo "type = ${INPUT_ENV_TYPE}"
	echo "host = ${INPUT_ENV_HOST}"
	echo "port = ${INPUT_ENV_PORT}"
	echo "user = ${INPUT_ENV_USER}"
	echo "pass = ${SECURE_PASS}"
} > "$HOME/.config/rclone/rclone.conf"

rclone mkdir "remote:${INPUT_ENV_REMOTE_ROOT}"

mkdir -p "${GITHUB_WORKSPACE}/remote"

rclone mount "remote:${INPUT_ENV_REMOTE_ROOT}" "${GITHUB_WORKSPACE}/remote" --daemon --log-file="${GITHUB_WORKSPACE}/rclone.log" -vv

echo "test" > "${GITHUB_WORKSPACE}/remote/file"

echo "${INPUT_MANIFEST}" > "${GITHUB_WORKSPACE}/file.manifest_input"

while read -r line; do
	if [ "${line::1}" != "+" ] && [ "${line::1}" != "-" ]; then
		cat "$line" > "${GITHUB_WORKSPACE}/file.manifest"
	else
		cp "${GITHUB_WORKSPACE}/file.manifest_input" "${GITHUB_WORKSPACE}/file.manifest"
	fi
	break;
done < "${GITHUB_WORKSPACE}/file.manifest_input"

rm -f "${GITHUB_WORKSPACE}/file.manifest_input"

## TODO: Do removals at the end

function process_line() {
	line="$1"
	echo "$line"
	return;
	operation="${line::1}"
	file="${line:2}"
	if [ "${operation}" == "*" ]; then
		dir="${GITHUB_WORKSPACE}/remote/${file}"
		if [ ! -d "${dir}" ]; then
			echo "mkdir -p '${dir}'"
			mkdir -p "${dir}"
		fi
	elif [ "${operation}" == "+" ]; then
		echo "cp -f '${INPUT_ENV_LOCAL_ROOT}/${file}' '${GITHUB_WORKSPACE}/remote/${file}'"
		cp -f "${INPUT_ENV_LOCAL_ROOT}/${file}" "${GITHUB_WORKSPACE}/remote/${file}"
	elif [ "${operation}" == "-" ]; then
		echo "rm -f '${GITHUB_WORKSPACE}/remote/${file}'"
		rm -f "${GITHUB_WORKSPACE}/remote/${file}"
	elif [ "${operation}" == "_" ]; then
		echo "dircleanup -f '${file}'"
		## TODO: Recurse into removing empty directories
	fi
}

declare -A pathsToCreate
declare -A uploads
declare -A removals
declare -A pathsToCleanup

while read -r line; do
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

rm -f "${GITHUB_WORKSPACE}/file.manifest"

for dir in "${!pathsToCreate[@]}"; do
	echo "* ${dir}" >> "${GITHUB_WORKSPACE}/file.manifest"
done

for file in "${!uploads[@]}"; do
	echo "+ ${file}" >> "${GITHUB_WORKSPACE}/file.manifest"
done

for file in "${!removals[@]}"; do
	echo "- ${file}" >> "${GITHUB_WORKSPACE}/file.manifest"
done

for dir in "${!pathsToCleanup[@]}"; do
	echo "_ ${dir}" >> "${GITHUB_WORKSPACE}/file.manifest"
done

JOBS_LIMIT=5

while read -r line; do
	if [ -z "${line}" ]; then
		continue;
	fi
	while [ "$(jobs -rp | wc -l)" -ge $JOBS_LIMIT ]; do
        sleep 1
    done

	process_line "$line" &
done < "${GITHUB_WORKSPACE}/file.manifest"

wait

ls -al "${GITHUB_WORKSPACE}/remote"

fusermount -u "${GITHUB_WORKSPACE}/remote"
