#!/usr/bin/env bash

if [[ "$INPUT_ENV_REMOTE_ROOT" == */ ]]; then
	INPUT_ENV_REMOTE_ROOT="${INPUT_ENV_REMOTE_ROOT%"/"}"
fi

CAPTURE=0
KEX_ALGORITHMS=""
KEY_ALGORITHMS=""
CIPHERS=""
MACS=""

while read -r line; do
	if [[ $line == "debug2: peer server KEXINIT"* ]]; then
		CAPTURE=1
		continue
	fi

	if [ "$CAPTURE" == "0" ]; then
		continue
	fi

	if [[ $line == "debug2: KEX algorithms: "* ]]; then
		KEX_ALGORITHMS="${line:24}"
		KEX_ALGORITHMS="${KEX_ALGORITHMS//,/ }"
		continue
	fi

	if [[ $line == "debug2: host key algorithms: "* ]]; then
		KEY_ALGORITHMS="${line:29}"
		KEY_ALGORITHMS="${KEY_ALGORITHMS//,/ }"
		continue
	fi

	if [[ $line == "debug2: ciphers ctos: "* ]]; then
		CIPHERS="${line:22}"
		CIPHERS="${CIPHERS//,/ }"
		continue
	fi

	if [[ $line == "debug2: MACs ctos: "* ]]; then
		MACS="${line:19}"
		MACS="${MACS//,/ }"
		continue
	fi
done < <(ssh -vvv -p "${INPUT_ENV_PORT}" "${INPUT_ENV_USER}@${INPUT_ENV_HOST}" "exit 0" 2>&1)

echo "KEX: $KEX_ALGORITHMS"
echo "KEY: $KEY_ALGORITHMS"
echo "CIPHERS: $CIPHERS"
echo "MACS: $MACS"

SECURE_PASS=$(echo "${INPUT_ENV_PASS}" | rclone obscure -)

mkdir -p "$HOME/.config/rclone"
{
	echo "[remote]"
	echo "type = ${INPUT_ENV_TYPE}"
	echo "host = ${INPUT_ENV_HOST}"
	echo "port = ${INPUT_ENV_PORT}"
	echo "user = ${INPUT_ENV_USER}"
	echo "pass = ${SECURE_PASS}"
	echo "ciphers = ${CIPHERS}"
	echo "key_exchange = ${KEX_ALGORITHMS}"
	echo "macs = ${MACS}"
	echo "known_hosts_file = ${HOME}/.config/rclone/known_hosts"
} > "$HOME/.config/rclone/rclone.conf"

ssh-keyscan -p "${INPUT_ENV_PORT}" "${INPUT_ENV_HOST}" > "${HOME}/.config/rclone/known_hosts"

rclone mkdir "remote:${INPUT_ENV_REMOTE_ROOT}"

mkdir -p "${GITHUB_WORKSPACE}/remote"

rclone mount "remote:${INPUT_ENV_REMOTE_ROOT}" "${GITHUB_WORKSPACE}/remote" --daemon --log-file="${GITHUB_WORKSPACE}/rclone.log" -vv

echo "test" > "${GITHUB_WORKSPACE}/remote/file"

dd if=/dev/zero of="${GITHUB_WORKSPACE}/remote/test-1M.bin" bs=1K count=1 oflag=dsync
dd if=/dev/zero of="${GITHUB_WORKSPACE}/remote/test-1M.bin" bs=1K count=10 oflag=dsync
dd if=/dev/zero of="${GITHUB_WORKSPACE}/remote/test-1M.bin" bs=1K count=100 oflag=dsync
dd if=/dev/zero of="${GITHUB_WORKSPACE}/remote/test-1M.bin" bs=1M count=1 oflag=dsync
dd if=/dev/zero of="${GITHUB_WORKSPACE}/remote/test-10M.bin" bs=1M count=10 oflag=dsync
dd if=/dev/zero of="${GITHUB_WORKSPACE}/remote/test-100M.bin" bs=1M count=100 oflag=dsync

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
