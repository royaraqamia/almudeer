# Production Dockerfile for Al-Mudeer Backend
# Optimized for Railway deployment with SSL support

FROM python:3.12-slim

# Set environment variables
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

# Install system dependencies
# libssl-dev and build-essential are CRITICAL for telethon/cryptg
# libmagic1 is required for python-magic (file content validation)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libssl-dev \
    gcc \
    libmagic1 \
    && rm -rf /var/lib/apt/lists/*

# Install python dependencies
COPY requirements.txt .
RUN pip install --upgrade pip && \
    pip install -r requirements.txt

# Copy application code
COPY . .

# Create startup script that runs migrations then starts the app
RUN printf '#!/bin/bash\nset -e\n\necho "Running database migrations..."\nalembic upgrade head || echo "Warning: Alembic migration failed"\necho "Starting application server..."\nexec python -m uvicorn main:app --host 0.0.0.0 --port $PORT\n' > /app/start.sh && chmod +x /app/start.sh

# Run startup script
CMD ["/app/start.sh"]
