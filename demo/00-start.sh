#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/common.inc"
dc config --quiet
dc up -d --build --wait --wait-timeout 120
dc ps -a
printf '\nAPI заказов: %s\nAPI уведомлений: %s\n' "$orders" "$notifications"
printf 'Swagger UI: http://127.0.0.1:%s/\n' "$swagger_port"
