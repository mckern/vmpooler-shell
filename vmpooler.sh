#!/bin/bash

if [ -f ~/.pooler ]; then
  source ~/.pooler
fi

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


function vmpooler_delete {
  local host="${1:-UNDEFINED}"

  if [[ ${host} == UNDEFINED ]]; then
    echo "please provide the name of a VM Pooler host to delete" >&2
  fi

  curl \
    --insecure \
    --request DELETE \
    --header "X-AUTH-TOKEN:${VMPOOLER_TOKEN}" \
    --url "${VMPOOLER_URL}/vm/${host}"
  return $?
}

function vmpooler_checkout {
  local platform_tag="${1:-UNDEFINED}"

  if [[ ${platform_tag} == UNDEFINED ]]; then
    echo "please provide a platform tag to checkout" >&2
    return 1
  fi

  curl \
    --insecure \
    --request POST \
    --header "X-AUTH-TOKEN:${VMPOOLER_TOKEN}" \
    --url "${VMPOOLER_URL}/vm/${platform_tag}"
  return $?
}

function vmpooler_reserve {
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
