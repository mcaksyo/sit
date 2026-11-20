#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname -- "${BASH_SOURCE[0]}")/.."
project=${SIT_PROJECT:-microservices-lab}
orders_port=${ORDERS_PORT:-8001}
notifications_port=${NOTIFICATIONS_PORT:-8002}
rabbit_ui_port=${RABBITMQ_UI_PORT:-15672}
swagger_port=${SWAGGER_PORT:-8088}
orders="http://127.0.0.1:$orders_port/api/orders"
notifications="http://127.0.0.1:$notifications_port/api/notifications"
customer_id=$((1000000000 + $(date +%s) % 1000000000))

docker_cmd() {
  if (( EUID == 0 )) || [[ -w /var/run/docker.sock ]]; then
    docker "$@"
  else
    sudo -n docker "$@"
  fi
}

dc() {
  if (( EUID == 0 )) || [[ -w /var/run/docker.sock ]]; then
    env ORDERS_PORT="$orders_port" NOTIFICATIONS_PORT="$notifications_port" \
      RABBITMQ_UI_PORT="$rabbit_ui_port" SWAGGER_PORT="$swagger_port" docker compose -p "$project" "$@"
  else
    sudo -n env ORDERS_PORT="$orders_port" NOTIFICATIONS_PORT="$notifications_port" \
      RABBITMQ_UI_PORT="$rabbit_ui_port" SWAGGER_PORT="$swagger_port" docker compose -p "$project" "$@"
  fi
}

create_order() {
  curl -fsS --max-time 10 "$orders" -H 'Content-Type: application/json' \
    -d "{\"customer_id\":$customer_id,\"amount\":\"${1:-1200.50}\"}"
}

show_json() {
  python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin),ensure_ascii=False,indent=2))'
}

order_id() {
  python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])'
}

queue_info() {
  dc exec -T -u rabbitmq rabbitmq rabbitmqctl -q list_queues name messages_ready messages_unacknowledged
}

wait_notice() {
  local id=$1 text=$2 result
  for ((attempt=0; attempt<20; attempt++)); do
    if result=$(curl -fsS --max-time 3 "$notifications?order_id=$id" 2>/dev/null) &&
       python3 -c 'import json,sys; sys.exit(not any(sys.argv[1] in x["message"] for x in json.load(sys.stdin)))' "$text" <<< "$result"; then
      show_json <<< "$result"
      return 0
    fi
    sleep 1
  done
  printf 'Уведомление по заказу %s не появилось. Проверь журналы notifications.\n' "$id" >&2
  return 1
}
