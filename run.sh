#!/usr/bin/env bash

if [[ "$INPUT_ENV_REMOTE_ROOT" == */ ]]; then
	INPUT_ENV_REMOTE_ROOT="${INPUT_ENV_REMOTE_ROOT%"/"}"
fi

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

bash "$GITHUB_ACTION_PATH/process-manifest.sh"

fusermount -u "${GITHUB_WORKSPACE}/remote"
