#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/common.inc"
trap 'dc start notifications >/dev/null || true' EXIT
dc stop notifications
result=$(create_order 1750.00)
show_json <<< "$result"
id=$(order_id <<< "$result")
echo 'Очередь при остановленном обработчике'
queue_info
dc start notifications
echo 'Запись в БД уведомлений после запуска'
wait_notice "$id" "Создан заказ №$id"
dc exec -T notifications-db psql -U notifications -d notifications \
  -c "SELECT order_id, message FROM notifications WHERE order_id = $id;"
echo 'Очередь после обработки'
queue_info
trap - EXIT
