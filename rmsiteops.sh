#!/bin/bash

set -e

eval $(azd env get-values)

: ${RM_REPOSITORY=https://github.com/yaegashi/dx2devops-rm-docker}
: ${RM_REF=main}
: ${REDMINE_REPOSITORY=https://github.com/redmica/redmica}
: ${REDMINE_REF=v3.0.3}

: ${NOPROMPT=false}
: ${VERBOSE=false}
: ${AZ_ARGS="-g $AZURE_RESOURCE_GROUP_NAME -n $AZURE_CONTAINER_APPS_APP_NAME"}
: ${AZ_REVISION=}
: ${AZ_REPLICA=}
: ${AZ_CONTAINER=redmine}

NL=$'\n'

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
		[yY]) return
	esac
	exit 1
}

app_hostname() {
	HOSTNAME=$(az containerapp hostname list $AZ_ARGS --query [0].name -o tsv)
	if test -z "$HOSTNAME"; then
		HOSTNAME=$(az containerapp show $ARGS --query properties.configuration.ingress.fqdn -o tsv)
	fi
	echo $HOSTNAME
}

cmd_rmops_dbinit() {
	BASE_STORAGE_ACCOUNT_NAME=$(az group show -g $BASE_RESOURCE_GROUP_NAME --query tags.STORAGE_ACCOUNT_NAME -o tsv)
	EXPIRY=$(date -u -d '5 minutes' '+%Y-%m-%dT%H:%MZ')
	SAS=$(az storage container generate-sas --only-show-errors --account-name $BASE_STORAGE_ACCOUNT_NAME --name secrets --permissions r --expiry $EXPIRY --https-only --output tsv)
	URL="https://${BASE_STORAGE_ACCOUNT_NAME}.blob.core.windows.net/secrets"
	# Pipe the shell script to the interactive shell in the container.
	# `sleep 10` is needed to wait for the interactive shell to be ready.
	# `script` tricks the Azure CLI into thinking it's in an interactive session.
	# `--command 'sh -c cat|sh'` is a hack to force sh to be non-interactive.
	{
		sleep 10
		cat <<-EOF
		URL="$URL"
		SAS="$SAS"
		DB_ADMIN_USER=\$(curl -s "\$URL/DB_ADMIN_USER?\$SAS")
		DB_ADMIN_PASS=\$(curl -s "\$URL/DB_ADMIN_PASS?\$SAS")
		rmops dbinit "\$DB_ADMIN_USER" "\$DB_ADMIN_PASS"
		EOF
	} | run script -q -c "az containerapp exec $AZ_ARGS --command 'sh -c cat|sh'"
	rm -f typescript
}

cmd_meid_update() {
	HOSTNAME=$(app_hostname)
	URI="https://${HOSTNAME}/.auth/login/aad/callback"
	URIS=$(az ad app show --id $MS_CLIENT_ID --query web.redirectUris -o tsv)
	URIS=$(echo "${URI}${NL}${URIS}" | sort | uniq)
	msg "ME-ID App Client ID:    ${MS_CLIENT_ID}"
	msg "ME-ID App Redirect URI: ${URI}"
	msg "Updating new Redirect URIs:${NL}${URIS}"
	confirm
	az ad app update --id $MS_CLIENT_ID --web-redirect-uris ${URIS}
}

cmd_data_get() {
	if test $# -lt 2; then
		msg 'Specify remote/local paths'
		exit 1
	fi
	run az storage file download --only-show-errors --account-name $AZURE_STORAGE_ACCOUNT_NAME -s data -p "$1" --dest "$2" >/dev/null
}

cmd_data_put() {
	if test $# -lt 2; then
		msg 'Specify remote/local paths'
		exit 1
	fi
	run az storage file upload --only-show-errors --account-name $AZURE_STORAGE_ACCOUNT_NAME -s data -p "$1" --source "$2" >/dev/null
}

cmd_acr_token() {
	PASSWORD=$(az acr token create --subscription ${AZURE_SUBSCRIPTION_ID} --registry ${BASE_CONTAINER_REGISTRY_NAME} --name ${BASE_CONTAINER_REGISTRY_TOKEN_NAME} --scope-map ${BASE_CONTAINER_REGISTRY_SCOPE_MAP_NAME} --query 'credentials.passwords[0].value' --output tsv)
	az keyvault secret set --subscription ${AZURE_SUBSCRIPTION_ID} --vault-name ${AZURE_KEY_VAULT_NAME} --name APP-CR-PASS --value "${PASSWORD}" >/dev/null
}

cmd_acr_push() {
	if ! test -d rm; then
		git clone $RM_REPOSITORY -b $RM_REF rm
	fi
	if ! test -d rm/redmine; then
		git clone $REDMINE_REPOSITORY -b $REDMINE_REF rm/redmine
	fi
	IMAGE=${BASE_CONTAINER_REGISTRY_ENDPOINT}/${BASE_CONTAINER_REGISTRY_SCOPE_MAP_NAME}
	TAG=$(date --utc +%Y%m%dT%H%M%SZ)
	APP_IMAGE="${IMAGE}:${TAG}"
	run az acr login --subscription ${AZURE_SUBSCRIPTION_ID} --name ${BASE_CONTAINER_REGISTRY_NAME}
	run docker build rm -t ${APP_IMAGE}
	run docker push ${APP_IMAGE}
	run azd env set APP_IMAGE ${APP_IMAGE}
}

cmd_aca_show() {
	run az containerapp show -g $AZURE_RESOURCE_GROUP_NAME -n $AZURE_CONTAINER_APPS_APP_NAME
}

cmd_aca_revisions() {
	ARGS="$AZ_ARGS"
	if ! $VERBOSE; then
		ARGS="$ARGS --query [].{revision:name,created:properties.createdTime,state:properties.runningState,weight:properties.trafficWeight} -o table"
	fi
	run az containerapp revision list $ARGS
}

cmd_aca_replicas() {
	ARGS="$AZ_ARGS"
	if test -n "$AZ_REVISION"; then
		ARGS="$ARGS --revision $AZ_REVISION"
	fi
	if ! $VERBOSE; then
		ARGS="$ARGS --query [].{replica:name,created:properties.createdTime,state:properties.runningState} -o table"
	fi
	run az containerapp replica list $ARGS
}

cmd_aca_hostnames() {
	ARGS="$AZ_ARGS"
	if ! $VERBOSE; then
		ARGS="$ARGS --query [].{hostname:name} -o table"
	fi
	run az containerapp hostname list $ARGS
}

cmd_aca_logs() {
	ARGS="$AZ_ARGS --container $AZ_CONTAINER"
	if test -n "$AZ_REVISION"; then
		ARGS="$ARGS --revision $AZ_REVISION"
	fi
	if test -n "$AZ_REPLICA"; then
		ARGS="$ARGS --replica $AZ_REPLICA"
	fi
	if ! $VERBOSE; then
		ARGS="$ARGS --format text"
	fi
	if test "$1" = 'follow'; then
		ARGS="$ARGS --follow"
	fi
	run az containerapp logs show $ARGS
}

cmd_aca_console() {
	ARGS="$AZ_ARGS --container $AZ_CONTAINER"
	if test -n "$AZ_REVISION"; then
		ARGS="$ARGS --revision $AZ_REVISION"
	fi
	if test -n "$AZ_REPLICA"; then
		ARGS="$ARGS --replica $AZ_REPLICA"
	fi
	CMD="$*"
	if test -z "$CMD"; then
		CMD=bash
	fi
	run az containerapp exec $ARGS --command "$CMD"
	run stty sane
}

cmd_aca_restart() {
	if test -z "$AZ_REVISION"; then
		AZ_REVISION=$(az containerapp show -g $AZURE_RESOURCE_GROUP_NAME -n $AZURE_CONTAINER_APPS_APP_NAME --query properties.latestRevisionName -o tsv)
	fi
	ARGS="$AZ_ARGS --revision $AZ_REVISION"
	msg "Restarting revision $AZ_REVISION..."
	confirm
	run az containerapp revision restart $ARGS
}

cmd_portal_base() {
	URL="https://portal.azure.com/#@${AZURE_TENANT_ID}/resource/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${BASE_RESOURCE_GROUP_NAME}"
	run xdg-open "$URL"
}

cmd_portal_site() {
	URL="https://portal.azure.com/#@${AZURE_TENANT_ID}/resource/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${AZURE_RESOURCE_GROUP_NAME}"
	run xdg-open "$URL"
}

cmd_portal_meid() {
	if test -z "$MS_TENANT_ID" -o -z "$MS_CLIENT_ID"; then
		msg 'Missing MS_TEANT_ID or MS_CLIENT_ID settings'
		exit 1
	fi
	URL="https://portal.azure.com/#@${MS_TENANT_ID}/view/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/~/Overview/appId/${MS_CLIENT_ID}"
	run xdg-open "$URL"
}

cmd_open() {
	HOSTNAME=$(app_hostname)
  	URL="https://${HOSTNAME}${APP_ROOT_PATH}"
	run xdg-open "$URL"
}

cmd_help() {
	msg "Usage: $0 <command> [options...] [args...]"
	msg "Options":
	msg "  --help,-h                  - Show this help"
	msg "  --no-prompt                - Do not ask for confirmation"
	msg "  --verbose, -v              - Show detailed output"
	msg "  --revision <name>          - Specify revision name"
	msg "  --replica <name>           - Specify replica name"
	msg "  --container <name>         - Specify container name"
	msg "Commands:"
	msg "  rmops-dbinit               - RMOPS: initialize app database"
	msg "  meid-update                - ME-ID: update app redirect URIs"
	msg "  data-get <remote> <local>  - Data: download file"
	msg "  data-put <remote> <local>  - Data: upload file"
	msg "  acr-token                  - ACR: update auth token"
	msg "  acr-push                   - ACR: build and push container image"
	msg "  aca-show                   - ACA: show app"
	msg "  aca-revisions              - ACA: list revisions"
	msg "  aca-replicas               - ACA: list replicas"
	msg "  aca-hostnames              - ACA: list hostnames"
	msg "  aca-restart                - ACA: restart revision"
	msg "  aca-logs [follow]          - ACA: show container logs"
	msg "  aca-console [command...]   - ACA: connect to container"
	msg "  portal-base                - Portal: open base resource group in browser"
	msg "  portal-site                - Portal: open site resource group in browser"
	msg "  portal-meid                - Portal: open ME-ID app registration in browser"
	msg "  open                       - open app in browser"
	exit $1
}

OPTIONS=$(getopt -o hqv -l help -l no-prompt -l verbose -l revision: -l replica: -l container: -- "$@")
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
		-v|--verbose)
			VERBOSE=true
			shift
			;;
		--revision)
			AZ_REVISION=$2
			shift 2
			;;
		--replica)
			AZ_REPLICA=$2
			shift 2
			;;
		--container)
			AZ_CONTAINER=$2
			shift 2
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
	rmops-dbinit)
		shift
		cmd_rmops_dbinit "$@"
		;;
	meid-update)
		shift
		cmd_meid_update "$@"
		;;
	data-get|download)
		shift
		cmd_data_get "$@"
		;;
	data-put|upload)
		shift
		cmd_data_put "$@"
		;;
	acr-token)
		shift
		cmd_acr_token "$@"
		;;
	acr-push)
		shift
		cmd_acr_push "$@"
		;;
	aca-show)
		shift
		cmd_aca_show "$@"
		;;
	aca-revisions)
		shift
		cmd_aca_revisions "$@"
		;;
	aca-replicas)
		shift
		cmd_aca_replicas "$@"
		;;
	aca-hostnames)
		shift
		cmd_aca_hostnames "$@"
		;;
	aca-logs)
		shift
		cmd_aca_logs "$@"
		;;
	aca-console)
		shift
		cmd_aca_console "$@"
		;;
	aca-restart)
		shift
		cmd_aca_restart "$@"
		;;
	portal-base)
		shift
		cmd_portal_base "$@"
		;;
	portal-site)
		shift
		cmd_portal_site "$@"
		;;
	portal-meid)
		shift
		cmd_portal_meid "$@"
		;;
	open)
		shift
		cmd_open "$@"
		;;
	*)
		msg "E: Invalid command: $1"
		cmd_help 1
		;;
esac
