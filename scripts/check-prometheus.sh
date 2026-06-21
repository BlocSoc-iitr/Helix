#!/usr/bin/env bash
set -euo pipefail

shopt -s nullglob

checked=0

run_promtool() {
	docker run --rm -v "$PWD:/workspace" -w /workspace prom/prometheus:latest promtool "$@"
}

config_patterns=(prometheus.yml prometheus.yaml prometheus/*.yml prometheus/*.yaml)
for pattern in "${config_patterns[@]}"; do
	for config in $pattern; do
		[[ -f "$config" ]] || continue
		run_promtool check config "$config"
		checked=1
	done
done

rules=()
for pattern in rules/*.yml rules/*.yaml prometheus/rules/*.yml prometheus/rules/*.yaml; do
	[[ -f "$pattern" ]] && rules+=("$pattern")
done
if ((${#rules[@]})); then
	run_promtool check rules "${rules[@]}"
	checked=1
fi

tests=()
for pattern in tests/*.test.yml tests/*.test.yaml prometheus/tests/*.test.yml prometheus/tests/*.test.yaml; do
	[[ -f "$pattern" ]] && tests+=("$pattern")
done
if ((${#tests[@]})); then
	run_promtool test rules "${tests[@]}"
	checked=1
fi

for fixture in fixtures/*.prom; do
	[[ -f "$fixture" ]] || continue
	docker run --rm -i prom/prometheus:latest promtool check metrics < "$fixture"
	checked=1
done

if ((checked == 0)); then
	echo "prometheus: nothing to check"
fi
