#!/usr/bin/env bash
set -euo pipefail

shopt -s nullglob

readonly dashboard_dir="${GRAFANA_DASHBOARD_DIR:-dashboards}"
readonly provisioning_dir="${GRAFANA_PROVISIONING_DIR:-provisioning}"
readonly grafana_image="${GRAFANA_IMAGE:-grafana/grafana:latest}"
readonly prometheus_datasource_uid="${PROMETHEUS_DATASOURCE_UID:-PBFA97CFB590B2093}"
readonly container_name="helix-grafana-$$"
readonly requested_grafana_port="${GRAFANA_PORT:-}"
readonly health_file="$(mktemp -t helix-grafana-health.XXXXXX)"
readonly grafana_search_file="$(mktemp -t helix-grafana-search.XXXXXX)"
readonly expected_dashboards_file="$(mktemp -t helix-grafana-expected.XXXXXX)"

log() {
	printf '[check-grafana] %s\n' "$*"
}

cleanup() {
	docker stop "$container_name" > /dev/null 2>&1 || true
	rm -f "$health_file" "$grafana_search_file" "$expected_dashboards_file"
}
trap cleanup EXIT

dashboards=()
if [[ -d "$dashboard_dir" ]]; then
	while IFS= read -r -d '' dashboard; do
		dashboards+=("$dashboard")
	done < <(find "$dashboard_dir" -type f -name '*.json' -print0 | sort -z)
fi

if ((${#dashboards[@]} == 0)); then
	log "no dashboards to check in $dashboard_dir"
	exit 0
fi

log "found ${#dashboards[@]} dashboard(s) under $dashboard_dir"

for dashboard in "${dashboards[@]}"; do
	log "validating dashboard JSON: $dashboard"
	jq empty "$dashboard"
	jq -e '
		(.uid | type == "string" and length > 0) and
		(.title | type == "string" and length > 0) and
		(.panels | type == "array")
	' "$dashboard" > /dev/null
	jq -e --arg uid "$prometheus_datasource_uid" '
		[.. | objects | .datasource? | select(type == "object" and .type == "prometheus")]
		| all(.uid == $uid)
	' "$dashboard" > /dev/null
	jq -c '{uid, title}' "$dashboard" >> "$expected_dashboards_file"
done

log "checking for duplicate dashboard UIDs"
jq -s -e '
	group_by(.uid)
	| map(select(length > 1))
	| length == 0
' "$expected_dashboards_file" > /dev/null

if [[ ! -d "$provisioning_dir" ]]; then
	log "provisioning directory not found: $provisioning_dir"
	exit 1
fi

grafana_port_publish="127.0.0.1::3000"
if [[ -n "$requested_grafana_port" ]]; then
	grafana_port_publish="127.0.0.1:${requested_grafana_port}:3000"
fi

log "starting Grafana container from $grafana_image"
docker run -d --rm \
	--name "$container_name" \
	-e GF_AUTH_ANONYMOUS_ENABLED=true \
	-e GF_AUTH_ANONYMOUS_ORG_ROLE=Admin \
	-e "GF_AUTH_ANONYMOUS_ORG_NAME=Main Org." \
	-e GF_AUTH_BASIC_ENABLED=false \
	-e GF_AUTH_DISABLE_LOGIN_FORM=true \
	-e GF_ANALYTICS_REPORTING_ENABLED=false \
	-e GF_ANALYTICS_CHECK_FOR_UPDATES=false \
	-e GF_ANALYTICS_CHECK_FOR_PLUGIN_UPDATES=false \
	-e GF_PATHS_PROVISIONING=/config \
	-p "$grafana_port_publish" \
	-v "$PWD/$provisioning_dir:/config:ro" \
	-v "$PWD/$dashboard_dir:/dashboards:ro" \
	"$grafana_image" > /dev/null

grafana_url="http://$(docker port "$container_name" 3000/tcp)"
log "Grafana is published at $grafana_url"

dashboards_loaded() {
	local missing=0

	curl -fsS "${grafana_url}/api/search" > "$grafana_search_file" || return 1
	jq empty "$grafana_search_file" || return 1

	while IFS= read -r expected_dashboard; do
		uid="$(jq -r '.uid' <<< "$expected_dashboard")"
		title="$(jq -r '.title' <<< "$expected_dashboard")"
		log "checking Grafana loaded dashboard: $title ($uid)"
		if ! jq -e --arg uid "$uid" --arg title "$title" '
			any(.[]; .uid == $uid and .title == $title)
		' "$grafana_search_file" > /dev/null; then
			log "dashboard not visible yet: $title ($uid)"
			missing=1
		fi
	done < "$expected_dashboards_file"

	return "$missing"
}

for _ in {1..60}; do
	if curl -fsS "${grafana_url}/api/health" > "$health_file" 2> /dev/null; then
		jq -e '.database == "ok"' "$health_file" > /dev/null
		log "Grafana health check passed"
		if dashboards_loaded; then
			log "all dashboards loaded successfully"
			exit 0
		fi
	fi
	sleep 2
done

log "Grafana did not load all dashboards before timeout; container logs follow"
docker logs "$container_name"
exit 1
