#!/bin/bash

# Start ngrok tunnel with your static domain, forwarding port 80
ngrok http --domain=koi-suitable-closely.ngrok-free.app 80 &

# Wait a bit for ngrok to initialize
sleep 5

# Start your bot container using Docker Compose in detached mode
docker compose up -d --build

# Optional: Tail logs so container output is visible (comment out if not wanted)
docker compose logs -f
