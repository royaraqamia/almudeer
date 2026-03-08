# Production Dockerfile for Al-Mudeer Backend
# Optimized for Railway deployment with SSL support

FROM python:3.11-slim

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

# Run application
# Shell form allows $PORT expansion
CMD python -m uvicorn main:app --host 0.0.0.0 --port $PORT
