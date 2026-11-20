#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/common.inc"
result=$(create_order 100.00)
id=$(order_id <<< "$result")
wait_notice "$id" "Создан заказ №$id" >/dev/null
event_id=$(python3 -c 'import uuid; print(uuid.uuid4().hex)')
dc exec -T -e "SIT_ORDER_ID=$id" -e "SIT_CUSTOMER_ID=$customer_id" \
  -e "SIT_EVENT_ID=$event_id" orders php <<'PHP'
<?php
require '/app/vendor/autoload.php';
(new Symfony\Component\Dotenv\Dotenv())->bootEnv('/app/.env');
$kernel = new App\Kernel($_SERVER['APP_ENV'], (bool) $_SERVER['APP_DEBUG']);
$kernel->boot();
$bus = $kernel->getContainer()->get('messenger.default_bus');
$event = new App\Message\OrderCreated(
    (int) getenv('SIT_ORDER_ID'), (int) getenv('SIT_CUSTOMER_ID'),
    '100.00', getenv('SIT_EVENT_ID'),
);
$bus->dispatch($event);
$bus->dispatch($event);
PHP

printf '\nДва сообщения с eventId %s\n' "$event_id"
for ((attempt=0; attempt<20; attempt++)); do
  queues=$(queue_info)
  if awk '$1 == "orders_notifications" && $2 == 0 && $3 == 0 {ok=1} END {exit !ok}' <<< "$queues"; then
    count=$(dc exec -T notifications-db psql -U notifications -d notifications -At \
      -c "SELECT count(*) FROM notifications WHERE event_id = '$event_id';")
    if [[ $count == 1 ]]; then
      echo 'В PostgreSQL ровно одна запись с этим eventId.'
      exit 0
    fi
  fi
  sleep 1
done
echo 'Проверка повторной доставки не прошла.' >&2
exit 1
