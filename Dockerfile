# Root Dockerfile for Railway monorepo deployment
# This delegates to the backend/Dockerfile

FROM python:3.11-slim

WORKDIR /app

# Copy only backend files
COPY backend/ ./

# Install dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Expose port
EXPOSE 8000

# Run the app
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
