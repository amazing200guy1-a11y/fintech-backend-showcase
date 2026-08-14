# ──────────────────────────────────────────────
# Mehd AI — Production Dockerfile
# ──────────────────────────────────────────────
# THE BATTERY SLOT: Build once, deploy anywhere.
# 
# Usage:
#   docker build -t mehd-ai-backend .
#   docker run --env-file .env -p 8000:8000 mehd-ai-backend
#
# Or use docker-compose (recommended):
#   docker compose up
# ──────────────────────────────────────────────

FROM python:3.12-slim AS base

# Security: Don't run as root
RUN groupadd -r mehd && useradd -r -g mehd -m mehd

# System deps & High-Throughput OS Limits (1,048,576 File Descriptors)
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/* \
    && echo "* soft nofile 1048576" >> /etc/security/limits.conf \
    && echo "* hard nofile 1048576" >> /etc/security/limits.conf \
    && echo "root soft nofile 1048576" >> /etc/security/limits.conf \
    && echo "root hard nofile 1048576" >> /etc/security/limits.conf \
    && echo "mehd soft nofile 1048576" >> /etc/security/limits.conf \
    && echo "mehd hard nofile 1048576" >> /etc/security/limits.conf

WORKDIR /app

# Install Python dependencies first (layer caching)
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Remove sensitive files from image
RUN rm -f .env .env.local .risk_kernel_state.json

# Create data directories
RUN mkdir -p /app/data && chown -R mehd:mehd /app

# Switch to non-root user
USER mehd

# Expose the API port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# Start the application with multi-worker ASGI scaling
ENV WORKERS=4
CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port 8000 --workers ${WORKERS:-4} --log-level info"]
