#!/bin/bash

set -e

eval $(azd env get-values)

: ${RM_REPOSITORY=https://github.com/yaegashi/azdops-rm-docker}
: ${RM_REF=main}
: ${REDMINE_REPOSITORY=https://github.com/redmica/redmica}
: ${REDMINE_REF=v3.1.0}

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
	LOCAL_SCRIPT=$(mktemp /tmp/rmops-dbinit-XXXXXXXX.sh)
	REMOTE_SCRIPT="wwwroot/tmp/${LOCAL_SCRIPT##*/}"
	cat <<-EOF >$LOCAL_SCRIPT
	URL="$URL"
	SAS="$SAS"
	DB_ADMIN_USER=\$(curl -s "\$URL/DB_ADMIN_USER?\$SAS")
	DB_ADMIN_PASS=\$(curl -s "\$URL/DB_ADMIN_PASS?\$SAS")
	rmops dbinit "\$DB_ADMIN_USER" "\$DB_ADMIN_PASS"
	EOF
	run az storage directory create --only-show-errors --account-name $AZURE_STORAGE_ACCOUNT_NAME -s data -n wwwroot/tmp >/dev/null
	run az storage file upload --only-show-errors --account-name $AZURE_STORAGE_ACCOUNT_NAME -s data -p $REMOTE_SCRIPT --source $LOCAL_SCRIPT >/dev/null
	run script -q -c "az containerapp exec $AZ_ARGS --command 'bash -e /home/site/$REMOTE_SCRIPT'"
	rm -f typescript
}

cmd_rmops_setup() {
	LOCAL_SCRIPT=$(mktemp /tmp/rmops-setup-XXXXXXXX.sh)
	REMOTE_SCRIPT="wwwroot/tmp/${LOCAL_SCRIPT##*/}"
	cat <<-EOF >$LOCAL_SCRIPT
	rmops setup
	rmops env set rails enable
	echo "######## Admin Password ########"
	tail -1 /home/site/wwwroot/etc/password.txt
	EOF
	run az storage directory create --only-show-errors --account-name $AZURE_STORAGE_ACCOUNT_NAME -s data -n wwwroot/tmp >/dev/null
	run az storage file upload --only-show-errors --account-name $AZURE_STORAGE_ACCOUNT_NAME -s data -p $REMOTE_SCRIPT --source $LOCAL_SCRIPT >/dev/null
	run script -q -c "az containerapp exec $AZ_ARGS --command 'bash -e /home/site/$REMOTE_SCRIPT'"
	rm -f typescript
}

cmd_rmops_passwd() {
	if test $# -lt 1; then
		msg 'Specify username'
		exit 1
	fi
	LOCAL_SCRIPT=$(mktemp /tmp/rmops-passwd-XXXXXXXX.sh)
	REMOTE_SCRIPT="wwwroot/tmp/${LOCAL_SCRIPT##*/}"
	cat <<-EOF >$LOCAL_SCRIPT
	rmops passwd "$@"
	echo "######## Admin Password ########"
	tail -1 /home/site/wwwroot/etc/password.txt
	EOF
	run az storage directory create --only-show-errors --account-name $AZURE_STORAGE_ACCOUNT_NAME -s data -n wwwroot/tmp >/dev/null
	run az storage file upload --only-show-errors --account-name $AZURE_STORAGE_ACCOUNT_NAME -s data -p $REMOTE_SCRIPT --source $LOCAL_SCRIPT >/dev/null
	run script -q -c "az containerapp exec $AZ_ARGS --command 'bash -e /home/site/$REMOTE_SCRIPT'"
	rm -f typescript
}

cmd_meid_redirect() {
	APP_HOSTNAME=$(app_hostname)
	URI="https://${APP_HOSTNAME}/.auth/login/aad/callback"
	URIS=$(az ad app show --id $MS_CLIENT_ID --query web.redirectUris -o tsv)
	URIS=$(echo "${URI}${NL}${URIS}" | sort | uniq)
	msg "ME-ID App Client ID:    ${MS_CLIENT_ID}"
	msg "ME-ID App Redirect URI: ${URI}"
	msg "Updating new Redirect URIs:${NL}${URIS}"
	confirm
	run az ad app update --id $MS_CLIENT_ID --web-redirect-uris $URIS
}

cmd_meid_secret() {
	APP_HOSTNAME=$(app_hostname)
	CRED_TIME=$(date +%s)
	CRED_NAME="$APP_HOSTNAME $CRED_TIME"
	msg "ME-ID App Client ID: ${MS_CLIENT_ID}"
	msg "Adding new Client Secret for $APP_HOSTNAME"
	confirm
	msg "ME-ID App new credential name: $CRED_NAME"
	PASSWORD=$(az ad app credential reset --id $MS_CLIENT_ID --append --display-name "$CRED_NAME" --end-date 2299-12-31 --query password -o tsv 2>/dev/null)
	run az keyvault secret set --vault-name $AZURE_KEY_VAULT_NAME --name MS-CLIENT-SECRET --file <(echo -n "$PASSWORD") >/dev/null
	run az containerapp revision copy $AZ_ARGS --revision-suffix $CRED_TIME >/dev/null
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
		msg 'E: Directory rm not found; run rm-clone first'
		exit 1
	fi
	IMAGE=${BASE_CONTAINER_REGISTRY_ENDPOINT}/${BASE_CONTAINER_REGISTRY_SCOPE_MAP_NAME}
	TAG=$(date --utc +%Y%m%dT%H%M%SZ)
	APP_IMAGE="${IMAGE}:${TAG}"
	run az acr login --subscription ${AZURE_SUBSCRIPTION_ID} --name ${BASE_CONTAINER_REGISTRY_NAME}
	run docker build rm -t ${APP_IMAGE}
	run docker push ${APP_IMAGE}
	run azd env set APP_IMAGE ${APP_IMAGE}
}

clone_plugin() {
	dir=${3-$(basename $1)}
	if test -d $dir; then
		if test -d $dir/.git; then
			run git -C $dir remote update
			run git -C $dir checkout -q $2
		fi
	else
		run git clone -q --filter blob:none $1 $dir
		run git -C $dir checkout -q $2
	fi
}

cmd_rm_clone() {
	if ! test -d rm; then
		run git clone $RM_REPOSITORY -b $RM_REF rm
	fi
	if ! test -d rm/redmine; then
		run git clone $REDMINE_REPOSITORY -b $REDMINE_REF rm/redmine
	fi
	cd rm/plugins
	clone_plugin https://github.com/agileware-jp/redmine_issue_templates 1.2.1
	clone_plugin https://github.com/farend/redmine_message_customize v1.1.0
	clone_plugin https://github.com/onozaty/redmine-view-customize v3.5.2 view_customize
	clone_plugin https://github.com/redmica/redmica_ui_extension v0.4.0
	clone_plugin https://github.com/redmica/redmine_ip_filter v1.1.0
	clone_plugin https://github.com/redmica/redmine_issues_panel v1.1.2
	clone_plugin https://github.com/vividtone/redmine_vividtone_my_page_blocks 1.3
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
	msg "  rmops-setup                - RMOPS: setup"
	msg "  rmops-passwd               - RMOPS: passwd"
	msg "  meid-redirect              - ME-ID: update app redirect URIs"
	msg "  meid-secret                - ME-ID: create new client secret"
	msg "  data-get <remote> <local>  - Data: download file"
	msg "  data-put <remote> <local>  - Data: upload file"
	msg "  rm-clone                   - RM: clone RM repository"
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
	rmops-setup)
		shift
		cmd_rmops_setup "$@"
		;;
	rmops-passwd)
		shift
		cmd_rmops_passwd "$@"
		;;
	meid-redirect)
		shift
		cmd_meid_redirect "$@"
		;;
	meid-secret)
		shift
		cmd_meid_secret "$@"
		;;
	data-get|download)
		shift
		cmd_data_get "$@"
		;;
	data-put|upload)
		shift
		cmd_data_put "$@"
		;;
	rm-clone)
		shift
		cmd_rm_clone "$@"
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
