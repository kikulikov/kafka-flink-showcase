#!/usr/bin/env bash

cd "$(dirname "$0")" || exit

echo
echo "Stopping the containers.."

docker compose --env-file docker-compose.env \
--file docker-compose-kafka.yml --file docker-compose-flink.yml down
