#!/usr/bin/env bash
set -euo pipefail

shopt -s nullglob

readonly prometheus_image="${PROMETHEUS_IMAGE:-prom/prometheus:latest}"

checked=0

log() {
	printf '[check-prometheus] %s\n' "$*"
}

run_promtool() {
	docker run --rm --entrypoint promtool -v "$PWD:/workspace:ro" -w /workspace "$prometheus_image" "$@"
}

collect_yaml_files() {
	local target_dir="$1"
	local maxdepth="$2"
	shift 2

	[[ -d "$target_dir" ]] || return 0

	find "$target_dir" -maxdepth "$maxdepth" -type f "$@" -print0 | sort -z
}

collect_recursive_yaml_files() {
	local target_dir="$1"
	shift

	[[ -d "$target_dir" ]] || return 0

	find "$target_dir" -type f "$@" -print0 | sort -z
}

configs=()
for config in prometheus.yml prometheus.yaml; do
	[[ -f "$config" ]] && configs+=("$config")
done

while IFS= read -r -d '' config; do
	configs+=("$config")
done < <(collect_yaml_files prometheus 1 \( -name '*.yml' -o -name '*.yaml' \) ! -name '*.test.yml' ! -name '*.test.yaml')

for config_dir in prometheus/config prometheus/configs; do
	while IFS= read -r -d '' config; do
		configs+=("$config")
	done < <(collect_recursive_yaml_files "$config_dir" \( -name '*.yml' -o -name '*.yaml' \) ! -name '*.test.yml' ! -name '*.test.yaml')
done

if ((${#configs[@]})); then
	log "found ${#configs[@]} Prometheus config file(s)"
	for config in "${configs[@]}"; do
		log "checking config: $config"
		run_promtool check config "$config"
	done
	checked=1
fi

rules=()
for rules_dir in rules prometheus/rules; do
	while IFS= read -r -d '' rule; do
		rules+=("$rule")
	done < <(collect_recursive_yaml_files "$rules_dir" \( -name '*.yml' -o -name '*.yaml' \))
done
if ((${#rules[@]})); then
	log "checking ${#rules[@]} Prometheus rule file(s)"
	run_promtool check rules "${rules[@]}"
	checked=1
fi

tests=()
for tests_dir in tests prometheus/tests; do
	while IFS= read -r -d '' test; do
		tests+=("$test")
	done < <(collect_recursive_yaml_files "$tests_dir" \( -name '*.test.yml' -o -name '*.test.yaml' \))
done
if ((${#tests[@]})); then
	log "running ${#tests[@]} Prometheus rule test file(s)"
	run_promtool test rules "${tests[@]}"
	checked=1
fi

fixtures=()
for fixtures_dir in fixtures prometheus/fixtures; do
	while IFS= read -r -d '' fixture; do
		fixtures+=("$fixture")
	done < <(find "$fixtures_dir" -type f -name '*.prom' -print0 2> /dev/null | sort -z)
done

if ((${#fixtures[@]})); then
	log "checking ${#fixtures[@]} Prometheus metric fixture(s)"
	for fixture in "${fixtures[@]}"; do
		log "checking metric fixture: $fixture"
		docker run --rm -i --entrypoint promtool "$prometheus_image" check metrics < "$fixture"
	done
	checked=1
fi

if ((checked == 0)); then
	log "nothing to check"
else
	log "all Prometheus checks passed"
fi
