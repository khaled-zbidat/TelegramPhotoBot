# Use an official Python runtime as base image
FROM python:3.10-slim

# Set working directory
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    libgl1-mesa-glx \
    libglib2.0-0 \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy only requirements.txt first (for better layer caching)
COPY ./polybot/requirements.txt ./requirements.txt

# Install Python dependencies
RUN pip install -r requirements.txt

# Copy the rest of the application code
COPY . .

# Run the bot
CMD ["python3", "-m", "polybot.app"]