FROM python:3.10-slim

WORKDIR /app

COPY . .

RUN apt-get update && apt-get install -y curl unzip \
    && pip install --no-cache-dir -r requirements.txt

# Install ngrok
RUN curl -s https://ngrok-agent.s3.amazonaws.com/ngrok.asc | tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null \
    && echo "deb https://ngrok-agent.s3.amazonaws.com buster main" | tee /etc/apt/sources.list.d/ngrok.list \
    && apt-get update && apt-get install -y ngrok

EXPOSE 8443

CMD ["./start.sh"]
