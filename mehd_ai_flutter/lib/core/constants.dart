/// FILE 2 — constants.dart
///
/// Build Debrief:
/// This file stores all hardcoded configurations and application-wide variables. 
/// Centralizing API URLs, symbol lists, and risk parameters means we only have to 
/// update them in one place. If the kill-switch threshold changes from 3% to 4%, 
/// we change it here, and the entire app respects the new rule.

class AppConstants {
  // ── NETWORK CONFIGURATION ──────────────────────────────────────────────────
  // STEP 1 OF CLOUD DEPLOYMENT: Change this one line.
  //
  // LOCAL DEV  (your laptop on WiFi):
  //   static const String baseUrl = 'http://10.33.159.35:8000';
  //
  // CLOUD (Railway / Render / GCP — after deployment):
  //   static const String baseUrl = 'https://YOUR-APP-NAME.up.railway.app';
  //
  static const String baseUrl = 'http://10.33.159.35:8000'; // ← CHANGE THIS FOR CLOUD
  static const String wsUrl = '$baseUrl/stream'; // Base path for SSE stream endpoints

  // Core Major Asset Pairs (Forex, Commodities, Crypto, Indices)
  static const List<String> symbols = [
    'EUR/USD',
    'GBP/USD',
    'AUD/USD',
    'USD/JPY',
    'USD/CAD',
    'XAU/USD',
    'BTC/USD',
    'ETH/USD',
    'SPX500',
    'NAS100',
  ];

  // AI Models by Layer (11 Specialized Agents)
  static const List<String> sentimentModels = ['DON', 'PHANTOM', 'ORACLE'];
  static const List<String> strategyModels = ['CAESAR', 'SAGE', 'GUARDIAN'];
  static const List<String> mathModels = ['TITAN', 'ATLAS', 'FORGE', 'THE DON', 'SENTINEL'];

  // Risk Kernel Constants
  static const double maxRiskPercent = 1.0;
  static const double killSwitchPercent = 3.0;
}

/// App-wide button state enum for trade execution flow.
enum ButtonState { locked, readyBuy, readySell, executing, filled, developing, vetoed }
