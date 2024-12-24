#!/bin/bash

set -e

: ${NOPROMPT=false}

msg() {
	echo ">>> $*" >&2
}

run() {
	msg "Running: $@"
	"$@"
}

confirm() {
	if $NOPROMPT; then
		return
	fi
	read -p ">>> Continue? [y/N] " -n 1 -r >&2
	echo >&2
	case "$REPLY" in
		y) return ;;
	esac
	exit 1
}

enable_remote_env() {
	msg 'Updating ~/.azd/config.yaml to enable the azd remote env'
	confirm
	run azd config set state.remote.backend AzureBlobStorage
	run azd config set state.remote.config.accountName $1
}

disable_remote_env() {
	msg 'Updating ~/.azd/config.yaml to disable the azd remote env'
	confirm
	run azd config unset state
}

cmd_auth() {
	run azd config set auth.useAzCliAuth true
	msg 'You have to run "az login" to complete the auth setup'
}

cmd_load() {
	if test -z "$AZD_REMOTE_ENV_STORAGE_ACCOUNT_NAME"; then
		msg 'E: AZD_REMOTE_ENV_STORAGE_ACCOUNT_NAME is not set in the local env'
		exit 1
	fi
	enable_remote_env $AZD_REMOTE_ENV_STORAGE_ACCOUNT_NAME
	if test -n "$AZD_REMOTE_ENV_NAME"; then
		run azd env select $AZD_REMOTE_ENV_NAME
	fi
	run azd env list
}

cmd_save() {
	if ! eval $(azd env get-values); then
		msg 'E: Failed to get values from the azd local env'
		exit 1
	fi
	if test -z "$AZURE_STORAGE_ACCOUNT_NAME"; then
		msg 'E: AZURE_STORAGE_ACCOUNT_NAME is not set in the azd local env'
		exit 1
	fi
	enable_remote_env $AZURE_STORAGE_ACCOUNT_NAME
	run azd env refresh
	run azd env list
	msg 'Set the following variables to load the remote env in future:'
	msg "  AZD_REMOTE_ENV_STORAGE_ACCOUNT_NAME=$AZURE_STORAGE_ACCOUNT_NAME"
	msg "  AZD_REMOTE_ENV_NAME=$AZURE_ENV_NAME"
}

cmd_clear() {
	disable_remote_env
	run azd env list
}

cmd_help() {
	msg "Usage: $0 <command> [options...] [args...]"
	msg "Options:"
	msg "  --help,-h     - Show this help"
	msg "  --no-prompt   - Do not ask for confirmation"
	msg "Commands:"
	msg "  auth          - Set up azd config for auth"
	msg "  load          - Load the azd remote env"
	msg "  save          - Save the azd remote env"
	msg "  clear         - Clear the azd remote env"
	exit $1
}

OPTIONS=$(getopt -o h -l help,no-prompt -- "$@")
if test $? -ne 0; then
	cmd_help 1
fi

eval set -- "$OPTIONS"

while true; do
	case "$1" in
		-h|--help)
			cmd_help 0
			;;
		--no-prompt)
			NOPROMPT=true
			shift
			;;
		--)
			shift
			break
			;;
		*)
			msg "E: Invalid option: $1"
			cmd_help 1
			;;
	esac
done

if test $# -eq 0; then
	msg "E: Missing command"
	cmd_help 1
fi

case "$1" in
	auth)
		shift
		cmd_auth "$@"
		;;
	load)
		shift
		cmd_load "$@"
		;;
	save)
		shift
		cmd_save "$@"
		;;
	clear)
		shift
		cmd_clear "$@"
		;;
	*)
		msg "E: Invalid command: $1"
		cmd_help 1
		;;
esac