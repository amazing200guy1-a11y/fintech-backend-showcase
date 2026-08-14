# Mehd AI -- Google Cloud Run Free-Tier Deployment Script (PowerShell)
# Run: .\deploy_cloud_run.ps1
# Prerequisite: Google Cloud SDK (gcloud) installed and authenticated

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  MEHD AI -- GOOGLE CLOUD RUN $0 FREE-TIER DEPLOYMENT" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

# 1. Project Configuration
$PROJECT_ID = Read-Host "Enter your Google Cloud Project ID (or press Enter for default)"
if ($PROJECT_ID) {
    gcloud config set project $PROJECT_ID
}

$REGION = "us-central1"
$SERVICE_NAME = "mehd-ai-backend"

Write-Host "`n[1/3] Building & Deploying Container to Google Cloud Run..." -ForegroundColor Yellow
gcloud run deploy $SERVICE_NAME `
    --source . `
    --region $REGION `
    --platform managed `
    --allow-unauthenticated `
    --min-instances 0 `
    --max-instances 10 `
    --concurrency 250 `
    --cpu 1 `
    --memory 512Mi `
    --set-env-vars "DEMO_MODE=true,STORAGE_BACKEND=firestore,WORKERS=4"

Write-Host "`n[2/3] Verifying Deployment Health Endpoint..." -ForegroundColor Yellow
$SERVICE_URL = (gcloud run services describe $SERVICE_NAME --platform managed --region $REGION --format 'value(status.url)')
Write-Host "Service Live URL: $SERVICE_URL" -ForegroundColor Green

Write-Host "`n[3/3] Deployment Successful!" -ForegroundColor Green
Write-Host "Your Mehd AI backend is running on Google Cloud Run Free Tier." -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
