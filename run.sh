#!/bin/bash
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

rclone mount "remote:${INPUT_ENV_REMOTE_ROOT}" "${GITHUB_WORKSPACE}/remote" --daemon

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

while read -r line; do
	if [ -z "${line}" ]; then
		continue;
	fi
	echo "$line";
	continue;
	operation="${line::1}"
	file="${line:2}"
	if [ "${operation}" == "+" ]; then
		dir=$(dirname "${GITHUB_WORKSPACE}/remote/${file}")
		if [ ! -d "${dir}" ]; then
			echo "mkdir -p '${dir}'"
			mkdir -p "${dir}"
		fi
		echo "cp -f '${INPUT_ENV_LOCAL_ROOT}/${file}' '${GITHUB_WORKSPACE}/remote/${file}'"
		cp -f "${INPUT_ENV_LOCAL_ROOT}/${file}" "${GITHUB_WORKSPACE}/remote/${file}"
	else
		echo "rm -f '${GITHUB_WORKSPACE}/remote/${file}'"
		rm -f "${GITHUB_WORKSPACE}/remote/${file}"
		
		## TODO: Recurse into removing empty directories
	fi
done < "${GITHUB_WORKSPACE}/file.manifest"

ls -al "${GITHUB_WORKSPACE}/remote"
