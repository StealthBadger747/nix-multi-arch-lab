#!/usr/bin/env bash
set -euo pipefail

if ! command -v nix >/dev/null 2>&1; then
  echo "error: nix is required" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required" >&2
  exit 1
fi

vulnix_cmd=()
if [[ -n "${VULNIX_BIN:-}" ]]; then
  if ! command -v "${VULNIX_BIN}" >/dev/null 2>&1; then
    echo "error: VULNIX_BIN was set but not found: ${VULNIX_BIN}" >&2
    exit 1
  fi
  vulnix_cmd=("${VULNIX_BIN}")
elif command -v vulnix >/dev/null 2>&1 && vulnix --version >/dev/null 2>&1; then
  vulnix_cmd=("vulnix")
else
  echo "warning: vulnix not usable from PATH; building upstream fallback binary" >&2
  vulnix_store_path="$(nix build --no-link --print-out-paths github:flyingcircusio/vulnix#vulnix^out)"
  vulnix_cmd=("${vulnix_store_path}/bin/vulnix")
fi

timestamp="${VULNIX_TIMESTAMP:-$(date -u +%Y%m%dT%H%M%SZ)}"
generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
output_dir="${VULNIX_OUTPUT_DIR:-reports/vulnix/${timestamp}}"
cache_dir="${VULNIX_CACHE_DIR:-${HOME}/.cache/vulnix}"
mkdir -p "${output_dir}" "${cache_dir}"

summary_json="${output_dir}/summary.json"
summary_md="${output_dir}/summary.md"
host_list_file="${output_dir}/hosts.txt"
tmp_records="$(mktemp)"
tmp_hosts=""

hosts_json="$(nix eval --json .#nixosConfigurations --apply 'x: builtins.attrNames x')"
echo "${hosts_json}" | jq -r '.[]' | sort > "${host_list_file}"

if [[ -n "${VULNIX_HOSTS:-}" ]]; then
  tmp_hosts="$(mktemp)"
  printf '%s\n' "${VULNIX_HOSTS}" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | sed '/^$/d' | sort -u > "${tmp_hosts}"
  grep -Fx -f "${tmp_hosts}" "${host_list_file}" > "${host_list_file}.filtered" || true
  mv "${host_list_file}.filtered" "${host_list_file}"
fi

cleanup() {
  rm -f "${tmp_records}"
  if [[ -n "${tmp_hosts}" ]]; then
    rm -f "${tmp_hosts}"
  fi
}
trap cleanup EXIT

whitelist_args=()
if [[ -n "${VULNIX_WHITELIST_URLS:-}" ]]; then
  IFS=',' read -ra items <<< "${VULNIX_WHITELIST_URLS}"
  for item in "${items[@]}"; do
    trimmed="$(printf '%s' "${item}" | xargs)"
    if [[ -n "${trimmed}" ]]; then
      whitelist_args+=("--whitelist" "${trimmed}")
    fi
  done
fi

scan_failed=0
while IFS= read -r host; do
  [[ -z "${host}" ]] && continue
  host_report="${output_dir}/${host}.json"

  echo "Scanning ${host}..."
  if ! drv_path="$(nix eval --raw ".#nixosConfigurations.${host}.config.system.build.toplevel.drvPath" 2>"${output_dir}/${host}.drv.err")"; then
    jq -cn \
      --arg host "${host}" \
      --arg error "failed to evaluate drvPath" \
      '{
        host: $host,
        status: "error",
        report_file: null,
        total_findings: 0,
        unique_cves: 0,
        critical: 0,
        high: 0,
        medium: 0,
        low: 0,
        top_cves: [],
        error: $error
      }' >> "${tmp_records}"
    scan_failed=1
    continue
  fi

  set +e
  "${vulnix_cmd[@]}" --json --cache-dir "${cache_dir}" "${whitelist_args[@]}" "${drv_path}" > "${host_report}" 2>"${output_dir}/${host}.scan.err"
  scan_rc=$?
  set -e

  if [[ "${scan_rc}" -ne 0 ]] && ! jq -e 'type == "array"' "${host_report}" >/dev/null 2>&1; then
    jq -cn \
      --arg host "${host}" \
      --arg error "vulnix scan failed" \
      '{
        host: $host,
        status: "error",
        report_file: null,
        total_findings: 0,
        unique_cves: 0,
        critical: 0,
        high: 0,
        medium: 0,
        low: 0,
        top_cves: [],
        error: $error
      }' >> "${tmp_records}"
    scan_failed=1
    continue
  fi

  jq -c \
    --arg host "${host}" \
    --arg report_file "$(basename "${host_report}")" \
    '
      def scored:
        [ .[] | (.cvssv3_basescore // {}) | to_entries[] | { id: .key, score: (.value | tonumber) } ]
        | unique_by(.id);
      def sorted_scored: scored | sort_by(-.score, .id);
      {
        host: $host,
        status: "ok",
        report_file: $report_file,
        total_findings: length,
        unique_cves: ([ .[] | .affected_by[]? ] | unique | length),
        critical: (scored | map(select(.score >= 9.0)) | length),
        high: (scored | map(select(.score >= 7.0 and .score < 9.0)) | length),
        medium: (scored | map(select(.score >= 4.0 and .score < 7.0)) | length),
        low: (scored | map(select(.score < 4.0)) | length),
        top_cves: (sorted_scored | .[0:10]),
        error: null
      }
    ' "${host_report}" >> "${tmp_records}"
done < "${host_list_file}"

jq -s \
  --arg timestamp "${timestamp}" \
  --arg generated_at "${generated_at}" \
  --arg repo "${GITHUB_REPOSITORY:-local}" \
  --arg ref "${GITHUB_REF_NAME:-local}" \
  '{
    timestamp: $timestamp,
    generated_at: $generated_at,
    repository: $repo,
    ref: $ref,
    hosts: .
  }' "${tmp_records}" > "${summary_json}"

{
  echo "# Vulnerability Summary"
  echo
  echo "- Generated at: ${generated_at}"
  echo "- Repository: ${GITHUB_REPOSITORY:-local}"
  echo "- Ref: ${GITHUB_REF_NAME:-local}"
  echo
  echo "## Host Overview"
  echo
  echo "| Host | Status | Findings | Unique CVEs | Critical | High | Medium | Low |"
  echo "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |"
  jq -r '.hosts[] | "| \(.host) | \(.status) | \(.total_findings) | \(.unique_cves) | \(.critical) | \(.high) | \(.medium) | \(.low) |"' "${summary_json}"
  echo
  echo "## Per-Host Top CVEs"
  echo
  jq -r '
    .hosts[]
    | "### " + .host + "\n"
      + (if .status != "ok" then
          "scan failed: " + (.error // "unknown error") + "\n"
        elif .top_cves | length == 0 then
          "no CVEs found\n"
        else
          (.top_cves[0:5] | map("- " + .id + " (CVSS " + (.score|tostring) + ")") | join("\n")) + "\n"
        end)
  ' "${summary_json}"
} > "${summary_md}"

echo "Summary JSON: ${summary_json}"
echo "Summary Markdown: ${summary_md}"

# Do not fail a scheduled report job because of findings. Only hard failures are non-zero.
if [[ "${scan_failed}" -ne 0 ]]; then
  echo "warning: one or more hosts could not be scanned; see *.err files in ${output_dir}" >&2
  exit 2
fi
