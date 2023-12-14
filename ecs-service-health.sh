#!/bin/bash

ecs_service_health_usage() {
  echo "Usage: $(basename "$0") CLUSTER_NAME SERVICE_NAME [TIMEOUT]"
}

ecs_service_health() {
  trap 'echo ERROR: Something happened on line "$LINENO" >&2' ERR

  local cluster_name=$1
  local service_name=$2
  local health_check_timeout=${3:-120}

  echo "INFO: Gathering data for $cluster_name/$service_name"

  local service_data; service_data=$(aws ecs describe-services --cluster "$cluster_name" --services "$service_name" | jq -e '.services[0]')
  local deployment_id; deployment_id=$(echo "$service_data" | jq -er '(.deployments[] | select(.status == "PRIMARY")).id')

  local loadbalancer_is_attached
  echo "$service_data" | jq -e '.loadBalancers | length > 0' > /dev/null &&
    loadbalancer_is_attached=true || loadbalancer_is_attached=false

  if "$loadbalancer_is_attached"; then
    local target_group_arn; target_group_arn=$(echo "$service_data" | jq -er '.loadBalancers[0].targetGroupArn')
    local container_port; container_port=$(echo "$service_data" | jq -er '.loadBalancers[0].containerPort')
  fi

  local start_time; start_time=$(date +%s)

  echo "INFO: loadbalancer_is_attached=$loadbalancer_is_attached"
  echo "INFO: Waiting $health_check_timeout seconds for the app to become healthy"

  while true; do
    echo -n .

    [[ -z ${tasks_list-} ]] &&
      local tasks_list; tasks_list=$(aws ecs list-tasks --cluster "$cluster_name" --started-by "$deployment_id" --query taskArns --output text)

    if [[ -n ${tasks_list-} ]]; then
      local tasks_list_arr; read -ra tasks_list_arr <<< "$tasks_list"
      local tasks_data; tasks_data=$(aws ecs describe-tasks --cluster "$cluster_name" --tasks "${tasks_list_arr[@]}")
    fi

    if [[ -n ${tasks_data-} ]]; then
      if "$loadbalancer_is_attached"; then
        local task_attachments; task_attachments=$(echo "$tasks_data" |
          jq '.tasks[0].attachments // empty'
        )

        [[ -n ${task_attachments-} ]] &&
          local task_ip_address; task_ip_address=$(echo "$task_attachments" |
            jq -r '[.[] | select(.type == "ElasticNetworkInterface")][0].details | [.[] | select(.name == "privateIPv4Address")][0].value // empty'
          )

        if [[ -n ${task_ip_address-} ]]; then
          local health_state; health_state=$(aws elbv2 describe-target-health --target-group-arn "$target_group_arn" --targets "Id=$task_ip_address, Port=$container_port" |
            jq -r '.TargetHealthDescriptions[0].TargetHealth.State'
          )

          [[ $health_state == "unused" ]] && unset tasks_list
          [[ $health_state == "draining" ]] && break
        fi
      else
        local health_state; health_state=$(echo "$tasks_data" | jq -er '.tasks[0].healthStatus | ascii_downcase')

        [[ $health_state == "unhealthy" ]] && break
      fi

      if [[ ${health_state-} == "healthy" ]]; then
        echo
        echo "INFO: $cluster_name/$service_name is healthy!"
        return 0
      fi
    fi

    local check_time; check_time=$(date +%s)

    (( check_time >= start_time + health_check_timeout )) && break

    sleep 1
  done

  echo
  echo "ERROR: $cluster_name/$service_name is not healthy! The state is ${health_state:-unknown}." >&2
  return 1
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail

  [[ ${RUNNER_DEBUG-} == "1" ]] && set -x

  [[ $# -ne 2 && $# -ne 3 ]] && { ecs_service_health_usage; exit 1; }

  ecs_service_health "$@"
fi
