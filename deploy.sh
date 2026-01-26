#!/bin/bash

echo "Pulling latest code..."
git pull

echo "Stopping containers..."
docker compose down

echo "Starting containers..."
docker compose up -d

docker compose logs -f --tail=200 web
