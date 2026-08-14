#!/bin/bash
# Mehd AI -- Google Cloud Run Free-Tier Deployment Script (Linux/Mac/Cloud Shell)
# Run: chmod +x deploy_cloud_run.sh && ./deploy_cloud_run.sh

set -e

echo "================================================================"
echo "  MEHD AI -- GOOGLE CLOUD RUN $0 FREE-TIER DEPLOYMENT"
echo "================================================================"

REGION="us-central1"
SERVICE_NAME="mehd-ai-backend"

echo ""
echo "[1/3] Deploying Container to Google Cloud Run (Free Tier Limits)..."
gcloud run deploy $SERVICE_NAME \
    --source . \
    --region $REGION \
    --platform managed \
    --allow-unauthenticated \
    --min-instances 0 \
    --max-instances 10 \
    --concurrency 250 \
    --cpu 1 \
    --memory 512Mi \
    --set-env-vars "DEMO_MODE=true,STORAGE_BACKEND=firestore,WORKERS=4"

echo ""
echo "[2/3] Fetching Service URL..."
SERVICE_URL=$(gcloud run services describe $SERVICE_NAME --platform managed --region $REGION --format 'value(status.url)')
echo "Service Live URL: $SERVICE_URL"

echo ""
echo "[3/3] Deployment Successful! Mehd AI is live."
echo "================================================================"
