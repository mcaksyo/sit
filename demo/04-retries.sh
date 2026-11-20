#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/common.inc"
dc exec -T notifications php bin/console messenger:setup-transports
queues=$(queue_info)
if ! awk '$1 == "orders_notifications_failed" && $2 == 0 && $3 == 0 {ok=1} END {exit !ok}' <<< "$queues"; then
  echo 'Очередь failed уже содержит сообщения. Для опыта запусти отдельный тестовый проект.' >&2
  exit 1
fi

trap 'dc up -d --wait --wait-timeout 40 notifications-db >/dev/null || true' EXIT
started=$(date -u +%Y-%m-%dT%H:%M:%SZ)
dc stop notifications-db
result=$(create_order 900.00)
show_json <<< "$result"
id=$(order_id <<< "$result")
for ((attempt=0; attempt<20; attempt++)); do
  queues=$(queue_info)
  if awk '$1 == "orders_notifications_failed" && $2 >= 1 {ok=1} END {exit !ok}' <<< "$queues"; then
    break
  fi
  sleep 1
done
printf '%s\n' "$queues"
dc logs --since "$started" --tail 25 notifications
awk '$1 == "orders_notifications_failed" && $2 == 1 {ok=1} END {exit !ok}' <<< "$queues"
dc up -d --wait --wait-timeout 40 notifications-db
trap - EXIT
dc exec -T notifications php bin/console messenger:consume failed --limit=1 --time-limit=15 -vv
wait_notice "$id" "Создан заказ №$id"
