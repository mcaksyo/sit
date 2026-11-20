#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/common.inc"

if [[ ${1:-} == --help || $# -gt 2 ]]; then
  echo 'Использование: bash demo/05-workers.sh [консьюмеры] [запросы]'
  [[ ${1:-} == --help ]]
  exit
fi

if (( $# == 0 )); then
  read -r -p 'Всего консьюмеров, включая основной [2]: ' consumers || true
  read -r -p 'Количество запросов на создание заказа [12]: ' requests || true
else
  consumers=$1
  requests=${2:-}
fi
consumers=${consumers:-2}
requests=${requests:-12}

if [[ ! $consumers =~ ^[1-9][0-9]{0,8}$ || ! $requests =~ ^[1-9][0-9]{0,8}$ ]]; then
  echo 'Введи положительные целые числа без ведущих нулей (до 9 цифр).' >&2
  exit 2
fi

dc up -d --no-recreate --wait --wait-timeout 40 notifications
workers=()
cleanup() {
  if (( ${#workers[@]} > 0 )); then
    docker_cmd rm -f "${workers[@]}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

for ((number=2; number<=consumers; number++)); do
  worker="$project-demo-worker-$$-$number"
  workers+=("$worker")
  dc run -d --no-deps --name "$worker" notifications \
    php bin/console messenger:consume async -vv >/dev/null
done

for worker in "${workers[@]}"; do
  for ((attempt=0; attempt<20; attempt++)); do
    logs=$(docker_cmd logs "$worker" 2>&1)
    [[ $logs == *'Consuming messages'* ]] && break
    sleep 1
  done
  if [[ $logs != *'Consuming messages'* ]]; then
    printf 'Консьюмер %s не запустился.\n%s\n' "$worker" "$logs" >&2
    exit 1
  fi
done

printf '\nКонсьюмеров: %d. Запросов: %d.\n' "$consumers" "$requests"
started=$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)
for ((number=0; number<requests; number++)); do
  create_order 100.00
  printf '\n'
  customer_id=$((customer_id + 1))
  sleep 0.3
done

count_handled() {
  awk '/OrderCreated.*handled successfully/ { count++ } END { print count+0 }'
}

for ((attempt=0; attempt<20; attempt++)); do
  logs=$(dc logs --since "$started" notifications 2>&1)
  counts=("$(count_handled <<< "$logs")")
  for worker in "${workers[@]}"; do
    logs=$(docker_cmd logs --since "$started" "$worker" 2>&1)
    counts+=("$(count_handled <<< "$logs")")
  done
  total=0
  for count in "${counts[@]}"; do
    total=$((total + count))
  done
  (( total >= requests )) && break
  sleep 1
done

printf '\nУспешные обработки OrderCreated по журналам за время опыта:\n'
printf 'Консьюмер 1 (основной): %d\n' "${counts[0]}"
for ((index=1; index<consumers; index++)); do
  printf 'Консьюмер %d: %d\n' "$((index + 1))" "${counts[index]}"
done
printf 'Всего: %d; отправлено запросов: %d.\n' "$total" "$requests"
if (( total < requests )); then
  echo 'Часть событий не обработана за время проверки. Проверь журналы notifications.' >&2
  exit 1
fi
