#!/usr/bin/env bash
set -euo pipefail

shopt -s nullglob

dashboards=(dashboards/*.json)
if ((${#dashboards[@]} == 0)); then
	echo "grafana: no dashboards to check"
	exit 0
fi

for dashboard in "${dashboards[@]}"; do
	jq empty "$dashboard"
	jq -e '.uid and .title and .panels' "$dashboard" > /dev/null
done

if [[ ! -d provisioning ]]; then
	echo "grafana: no provisioning directory"
	exit 0
fi

docker run -d --rm \
	--name helix-grafana \
	-e GF_SECURITY_ADMIN_USER=admin \
	-e GF_SECURITY_ADMIN_PASSWORD=admin \
	-p 3000:3000 \
	-v "$PWD/provisioning:/etc/grafana/provisioning:ro" \
	-v "$PWD/dashboards:/var/lib/grafana/dashboards:ro" \
	grafana/grafana-oss:latest > /dev/null

cleanup() {
	docker stop helix-grafana > /dev/null || true
}
trap cleanup EXIT

for _ in {1..60}; do
	if curl -fsS http://localhost:3000/api/health > /tmp/helix-grafana-health.json; then
		jq -e '.database == "ok"' /tmp/helix-grafana-health.json > /dev/null
		curl -fsS -u admin:admin http://localhost:3000/api/search > /tmp/helix-grafana-dashboards.json
		jq empty /tmp/helix-grafana-dashboards.json
		exit 0
	fi
	sleep 2
done

docker logs helix-grafana
exit 1
