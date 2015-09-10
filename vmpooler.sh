#!/bin/bash

# Requires `curl`, `basename` and `jq` to function

__config_dir="${HOME}/.vmpooler"
__config="${__config_dir}/config"
__lease_dir="${__config_dir}/leases"

# Create a lease directory
mkdir -p "${__lease_dir}"

# Source an existing VM Pooler configuration
if [ -f "${__config}" ]; then
  source "${__config}"
fi

### Utilities

function echo_parse_vm_hostname {
  local json="${1:-UNDEFINED}"
  local platform_tag="${2:-UNDEFINED}"

  if [[ ${json} == UNDEFINED ]]; then
    echo "please provide JSON output to parse" >&2
    return 1
  fi

  if [[ ${platform_tag} == UNDEFINED ]]; then
    echo "please provide a platform tag" >&2
    return 1
  fi

  echo "${json[@]}" | jq --exit-status --raw-output  ".\"${platform_tag}\".hostname | select(. == null | not)"
  return $?
}

function echo_parse_vm_domainname {
  local json="${1:-UNDEFINED}"

  if [[ ${json} == UNDEFINED ]]; then
    echo "please provide JSON output to parse" >&2
    return 1
  fi

  echo "${json[@]}" | jq --exit-status --raw-output  ".domain | select(. == null | not)"
  return $?
}

function echo_lease_path {
  local lease="${1:-UNDEFINED}"

  if [[ ${lease} == UNDEFINED ]]; then
    echo "please provide a lease name to lookup" >&2
    return 1
  fi

  if [ ! -d "${__lease_dir}" ]; then
    echo "cannot find directory to read leases from" >&2
    return 1
  fi

  echo "${__lease_dir}/${lease}"
  return $?
}

function create_vm_lease {
  local lease="${1:-UNDEFINED}"
  local lease_path

  if [[ ${lease} == UNDEFINED ]]; then
    echo "please provide a lease name to create" >&2
    return 1
  fi

  if [ ! -d "${__lease_dir}" ]; then
    echo "cannot find directory to write lease to" >&2
    return 1
  fi

  lease_path="$(echo_lease_path "${lease}")"
  if [ -e "${lease_path}" ]; then
    echo "lease '${lease}' already exists" >&2
    return 1
  fi

  echo "writing lease ${lease}"
  touch "${lease_path}"
  return $?
}

function destroy_vm_lease {
  local lease="${1:-UNDEFINED}"
  local lease_path

  if [[ ${lease} == UNDEFINED ]]; then
    echo "please provide a lease name to destroy" >&2
    return 1
  fi

  if [ ! -d "${__lease_dir}" ]; then
    echo "cannot find directory to remove lease from" >&2
    return 1
  fi

  lease_path="$(echo_lease_path "${lease}")"
  if [ ! -f "${lease_path}" ]; then
    echo "lease '${lease}' does not exist" >&2
    return 1
  fi

  echo "destroying lease ${lease}"
  rm -f "${lease_path}"
  return $?
}

function test_vmpooler_token {
  if [ -z "${VMPOOLER_TOKEN}" ]; then
    echo "no VM Pooler token found" >&2
    return 1
  fi
  return 0
}

### Pooler functions

function vmpooler_checkout {
  local platform_tag="${1:-UNDEFINED}"
  local json_output
  local return_value
  local vm_hostname
  local lease_path

  if [[ ${platform_tag} == UNDEFINED ]]; then
    echo "please provide a platform tag to checkout" >&2
    return 1
  fi

  if ! test_vmpooler_token; then
    echo "cannot find VM Pooler token, cannot check out pooler VM"
    return 1
  fi

  json_output="$(curl --insecure --silent --request POST --header "X-AUTH-TOKEN:${VMPOOLER_TOKEN}" --url "${VMPOOLER_URL}/vm/${platform_tag}")"
  return_value=$?

  if [[ $return_value == 0 ]]; then
    vm_hostname="$(echo_parse_vm_hostname "${json_output}" "${platform_tag}")"
    return_value=$?
  else
    echo "unable to check out instance of '${platform_tag}' host" >&2
    return 1
  fi

  if [[ $return_value == 0 ]]; then
    echo "checked out ${vm_hostname} (${platform_tag})"
    create_vm_lease "${vm_hostname}"
    return_value=$?
  else
    echo "unable to parse hostname for new instance of '${platform_tag}' host" >&2
    return 1
  fi

  if [[ $return_value == 0 ]]; then
    lease_path="$(echo_lease_path "${vm_hostname}")"
    echo_parse_vm_domainname "${json_output}" > "${lease_path}"
    return_value=$?
  else
    echo "unable to write local lease for host '${vm_hostname}'" >&2
    return 1
  fi

  return "${return_value}"
}

function vmpooler_destroy {
  local vm_hostname="${1:-UNDEFINED}"
  local return_value
  local lease_path

  if [[ ${vm_hostname} == UNDEFINED ]]; then
    echo "please provide the name of a VM Pooler host to destroy" >&2
  fi

  if ! test_vmpooler_token; then
    echo "cannot find VM Pooler token, cannot destroy pooler VM"
    return 1
  fi

  curl \
    --insecure \
    --silent \
    --request DELETE \
    --header "X-AUTH-TOKEN:${VMPOOLER_TOKEN}" \
    --url "${VMPOOLER_URL}/vm/${vm_hostname}" &> /dev/null

  return_value=$?

  if [[ $return_value != 0 ]]; then
    echo "unable to confirm destruction of host '${vm_hostname}'" >&2
    return 1
  fi

  destroy_vm_lease "${vm_hostname}"
  return $?
}

function vmpooler_leases {
  if [ ! -d "${__lease_dir}" ]; then
    echo "no lease directory found" >&2
    return 1
  fi

  find "${__lease_dir}" -type f -print0 | xargs -0 -n1 basename
  return 0
}

### Still in progress

function vmpooler_authorize {
  local user="${1:-UNDEFINED}"
  if [[ ${host} == UNDEFINED ]]; then
    echo "please provide the LDAP name to request a token for" >&2
    return 1
  fi

  curl \
    --insecure \
    --request POST \
    --user "${user}" \
    --url "${VMPOOLER_URL}/token"
  return $?
}

function vmpooler_status {
  local host="${1:-UNDEFINED}"

  if [[ ${host} == UNDEFINED ]]; then
    echo "please provide the name of a VM Pooler host to query" >&2
  fi

  curl \
    --insecure \
    --silent \
    --header "X-AUTH-TOKEN:${VMPOOLER_TOKEN}" \
    --url "${VMPOOLER_URL}/vm/${host}" |
    jq --exit-status --raw-output ".\"${host}\".state | select(. == null | not)"
  return $?
}

function vmpooler_lifespan {
  local host="${1:-UNDEFINED}"
  local lifespan="${2:-UNDEFINED}"

  if [[ ${host} == UNDEFINED ]]; then
    echo "please provide the name of a VM Pooler host to delete" >&2
    return 1
  fi

  if [[ ${lifespan} == UNDEFINED ]]; then
    echo "please provide the number of hours to reserve '${host}'" >&2
    return 1
  fi

  if ! test_vmpooler_token; then
    echo "cannot find VM Pooler token, cannot check out pooler VM"
    return 1
  fi

  curl \
    --insecure \
    --request PUT \
    --header "X-AUTH-TOKEN:${VMPOOLER_TOKEN}" \
    --data "{\"lifetime\":\"${lifespan}\"}" \
    --url "${VMPOOLER_URL}/vm/${host}"
  return $?
}

ssh_options='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ~/.ssh/jenkins_rsa'
alias vmpooler_ssh="ssh ${ssh_options}"
alias vmpooler_scp="scp ${ssh_options}"

function vmpooler {
  local action="${1:-UNDEFINED}"
  shift

  case "${action}" in
    checkout)
      vmpooler_checkout "${1}"
    ;;
    destroy)
      vmpooler_destroy "${1}"
    ;;
    status)
      vmpooler_status "${1}"
    ;;
    lifespan)
      vmpooler_lifespan "${1}"
    ;;
    leases)
      vmpooler_leases
    ;;
    *) echo "${@}" ;;
  esac
  return $?
}
