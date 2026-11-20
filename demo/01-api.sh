#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/common.inc"
echo 'POST /api/orders'
result=$(create_order)
show_json <<< "$result"
id=$(order_id <<< "$result")
echo "GET /api/orders/$id"
curl -fsS --max-time 10 "$orders/$id" | show_json
echo "PATCH /api/orders/$id/status"
curl -fsS --max-time 10 -X PATCH "$orders/$id/status" \
  -H 'Content-Type: application/json' -d '{"status":"paid"}' | show_json
echo "GET /api/notifications?order_id=$id"
wait_notice "$id" 'created на paid'
