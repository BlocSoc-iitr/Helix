#!/usr/bin/env bash
set -euo pipefail

shopt -s nullglob

readonly dashboard_dirs_spec="${DASHBOARD_DIRS:-${DASHBOARD_DIR:-dashboards}}"
readonly ethereum_package_repo="${ETHEREUM_PACKAGE_REPO:-https://github.com/ethpandaops/ethereum-package.git}"
readonly ethereum_package_ref="${ETHEREUM_PACKAGE_REF:-main}"
readonly ethereum_package_dir="${ETHEREUM_PACKAGE_DIR:-}"
readonly kurtosis_bin="${KURTOSIS:-kurtosis}"
readonly enclave="${ENCLAVE:-grafana-ethpkg-compat-$(date +%s)}"
readonly keep_enclave="${KEEP_ENCLAVE:-0}"
readonly replace_enclave="${REPLACE_ENCLAVE:-0}"
readonly package_dashboard_parent="${PACKAGE_DASHBOARD_PARENT:-src/grafana}"
readonly package_dashboard_dir_name="${PACKAGE_DASHBOARD_DIR_NAME:-additional-dashboards}"
readonly el_type="${EL_TYPE:-geth}"
readonly cl_type="${CL_TYPE:-lighthouse}"
readonly validator_count="${VALIDATOR_COUNT:-128}"
readonly scrape_interval="${SCRAPE_INTERVAL:-10s}"
readonly grafana_timeout_seconds="${GRAFANA_TIMEOUT_SECONDS:-240}"

log() {
	printf '[check-ethereum-package-compat] %s\n' "$*"
}

usage() {
	cat <<'EOF'

This checks dashboard packaging and loading only:
  - dashboard JSON files are valid
  - dashboard UIDs/titles are present and unique
  - dashboards can be staged into ethereum-package
  - grafana_params.additional_dashboards loads them
  - the running Grafana API can see the dashboards

Usage:
  ./scripts/check-ethereum-package-compat.sh

Common environment variables:
  DASHBOARD_DIR=dashboards
      Directory containing dashboard JSON files.

  DASHBOARD_DIRS=dir1:dir2
      Colon-separated dashboard directories. Overrides DASHBOARD_DIR.

  ETHEREUM_PACKAGE_DIR=/path/to/ethereum-package
      Use an existing local checkout instead of cloning.

  ETHEREUM_PACKAGE_REPO=https://github.com/ethpandaops/ethereum-package.git
  ETHEREUM_PACKAGE_REF=main
      Remote source to clone when ETHEREUM_PACKAGE_DIR is not set.

  ENCLAVE=ethpkg-compat REPLACE_ENCLAVE=1
      Use a stable enclave name and remove an existing one first.

  KEEP_ENCLAVE=1
      Leave the enclave running after the check for manual Grafana inspection.

  EL_TYPE=geth CL_TYPE=lighthouse
      Client pair used only to start a minimal ethereum-package network.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
	usage
	exit 0
fi

tmp_root="$(mktemp -d -t grafana-ethpkg-package.XXXXXX)"
args_file="$(mktemp -t grafana-ethpkg-args.XXXXXX.yaml)"
expected_dashboards_file="$(mktemp -t grafana-ethpkg-expected.XXXXXX)"
grafana_health_file="$(mktemp -t grafana-ethpkg-health.XXXXXX)"
grafana_search_file="$(mktemp -t grafana-ethpkg-search.XXXXXX)"

cleanup() {
	rm -f "$args_file" "$expected_dashboards_file" "$grafana_health_file" "$grafana_search_file"
	rm -rf "$tmp_root"

	if [[ "$keep_enclave" != "1" ]]; then
		"$kurtosis_bin" enclave rm -f "$enclave" > /dev/null 2>&1 || true
	else
		log "leaving enclave running: $enclave"
	fi
}
trap cleanup EXIT

require_command() {
	local command_name="$1"

	if ! command -v "$command_name" > /dev/null 2>&1; then
		log "required command not found: $command_name"
		exit 1
	fi
}

yaml_string() {
	jq -Rn --arg value "$1" '$value'
}

require_command "$kurtosis_bin"
require_command curl
require_command find
require_command jq
require_command tar

IFS=':' read -r -a dashboard_dir_inputs <<< "$dashboard_dirs_spec"
dashboard_dirs_abs=()
dashboards=()
all_files=()

for dashboard_dir in "${dashboard_dir_inputs[@]}"; do
	if [[ -z "$dashboard_dir" ]]; then
		continue
	fi

	if [[ ! -d "$dashboard_dir" ]]; then
		log "dashboard directory not found: $dashboard_dir"
		exit 1
	fi

	dashboard_dir_abs="$(cd "$dashboard_dir" && pwd -P)"
	dashboard_dirs_abs+=("$dashboard_dir_abs")

	while IFS= read -r -d '' dashboard; do
		dashboards+=("$dashboard")
	done < <(find "$dashboard_dir_abs" -type f -name '*.json' -print0 | sort -z)

	while IFS= read -r -d '' file; do
		all_files+=("$file")
	done < <(find "$dashboard_dir_abs" -type f -print0 | sort -z)
done

if ((${#dashboards[@]} == 0)); then
	log "no dashboard JSON files found under: ${dashboard_dirs_abs[*]:-$dashboard_dirs_spec}"
	exit 1
fi

log "checking dashboard package loading only"
log "found ${#dashboards[@]} dashboard JSON file(s) under: ${dashboard_dirs_abs[*]}"

if ((${#all_files[@]} != ${#dashboards[@]})); then
	log "warning: ethereum-package copies every file from additional_dashboards; non-JSON files will also be copied"
fi

duplicate_basenames="$(
	for file in "${all_files[@]}"; do
		printf '%s\n' "${file##*/}"
	done | sort | uniq -d
)"

if [[ -n "$duplicate_basenames" ]]; then
	log "dashboard file basenames must be unique because ethereum-package flattens additional dashboards into /dashboards"
	printf '%s\n' "$duplicate_basenames"
	exit 1
fi

for dashboard in "${dashboards[@]}"; do
	log "validating dashboard JSON: $dashboard"
	jq empty "$dashboard"
	jq -e '
		(.uid | type == "string" and length > 0) and
		(.title | type == "string" and length > 0) and
		(.panels | type == "array")
	' "$dashboard" > /dev/null
	jq -c '{uid, title}' "$dashboard" >> "$expected_dashboards_file"
done

log "checking for duplicate dashboard UIDs"
jq -s -e '
	group_by(.uid)
	| map(select(length > 1))
	| length == 0
' "$expected_dashboards_file" > /dev/null

if "$kurtosis_bin" enclave inspect "$enclave" > /dev/null 2>&1; then
	if [[ "$replace_enclave" == "1" ]]; then
		log "removing existing enclave before test: $enclave"
		"$kurtosis_bin" enclave rm -f "$enclave"
	else
		log "enclave already exists: $enclave"
		log "set REPLACE_ENCLAVE=1 to remove it automatically, or choose a different ENCLAVE"
		exit 1
	fi
fi

package_dir="$tmp_root/ethereum-package"
if [[ -n "$ethereum_package_dir" ]]; then
	if [[ ! -d "$ethereum_package_dir" ]]; then
		log "ETHEREUM_PACKAGE_DIR is not a directory: $ethereum_package_dir"
		exit 1
	fi

	log "copying local ethereum-package checkout: $ethereum_package_dir"
	mkdir -p "$package_dir"
	(
		cd "$ethereum_package_dir"
		tar --exclude='.git' -cf - .
	) | (
		cd "$package_dir"
		tar -xf -
	)
else
	require_command git
	log "cloning ethereum-package $ethereum_package_ref from $ethereum_package_repo"
	git clone --depth 1 --branch "$ethereum_package_ref" "$ethereum_package_repo" "$package_dir"
fi

package_dashboard_dir="$package_dir/$package_dashboard_parent/$package_dashboard_dir_name"
mkdir -p "$package_dashboard_dir"
for dashboard_dir_abs in "${dashboard_dirs_abs[@]}"; do
	cp -R "$dashboard_dir_abs"/. "$package_dashboard_dir"/
done

cat > "$args_file" <<YAML
participants:
  - el_type: $(yaml_string "$el_type")
    cl_type: $(yaml_string "$cl_type")
    validator_count: $validator_count
    prometheus_config:
      scrape_interval: $(yaml_string "$scrape_interval")
      labels: {}

network_params:
  seconds_per_slot: 12

additional_services:
  - prometheus
  - grafana

grafana_params:
  additional_dashboards:
    - $(yaml_string "$package_dashboard_dir_name")
YAML

log "starting ethereum-package enclave: $enclave"
log "using dashboard source(s): ${dashboard_dirs_abs[*]}"
log "copied dashboards into package path: $package_dashboard_parent/$package_dashboard_dir_name"
"$kurtosis_bin" run \
	--enclave "$enclave" \
	"$package_dir" \
	--args-file "$args_file"

grafana_url="$("$kurtosis_bin" port print "$enclave" grafana http)"
log "Grafana is published at $grafana_url"

deadline=$((SECONDS + grafana_timeout_seconds))
while ((SECONDS < deadline)); do
	if curl -fsS "${grafana_url}/api/health" > "$grafana_health_file" 2> /dev/null; then
		if jq -e '.database == "ok"' "$grafana_health_file" > /dev/null; then
			log "Grafana health check passed"
			break
		fi
	fi
	sleep 2
done

if ((SECONDS >= deadline)); then
	log "Grafana did not become healthy before timeout"
	exit 1
fi

curl -fsS "${grafana_url}/api/search?type=dash-db" > "$grafana_search_file"
jq empty "$grafana_search_file" > /dev/null

missing=0
while IFS= read -r expected_dashboard; do
	uid="$(jq -r '.uid' <<< "$expected_dashboard")"
	title="$(jq -r '.title' <<< "$expected_dashboard")"
	log "checking ethereum-package loaded dashboard: $title ($uid)"

	if ! jq -e --arg uid "$uid" --arg title "$title" '
		any(.[]; .uid == $uid and .title == $title)
	' "$grafana_search_file" > /dev/null; then
		log "dashboard not found in ethereum-package Grafana: $title ($uid)"
		missing=1
		continue
	fi

	curl -fsS "${grafana_url}/api/dashboards/uid/${uid}" \
		| jq -e --arg uid "$uid" --arg title "$title" '
			.dashboard.uid == $uid and .dashboard.title == $title
		' > /dev/null
done < "$expected_dashboards_file"

if ((missing)); then
	log "one or more dashboards failed to load through ethereum-package"
	exit 1
fi

log "all dashboards loaded through ethereum-package successfully"
log "compatibility check passed"
