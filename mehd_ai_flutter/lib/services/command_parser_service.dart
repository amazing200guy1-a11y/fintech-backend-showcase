import 'package:mehd_ai_flutter/models/slash_command.dart';

class CommandParserService {
  static const List<String> availableCommands = [
    '/long', '/short', '/close', '/nuke', '/bank50', '/be', '/breakeven', '/risk', '/shield', '/trail', '/help',
    '/xauusd', '/eurusd', '/gbpusd', '/audusd', '/usdcad', '/usdjpy', '/btcusd', '/ethusd', '/nas100',
    '/xau/usd', '/eur/usd', '/gbp/usd', '/aud/usd', '/usd/cad', '/usd/jpy', '/btc/usd', '/eth/usd',
  ];

  /// Helper to normalize slash-less symbols into standard pair format (e.g. XAUUSD -> XAU/USD)
  static String normalizeSymbol(String raw) {
    final upper = raw.trim().toUpperCase().replaceAll('/', '');
    if (upper == 'XAUUSD' || upper == 'GOLD') return 'XAU/USD';
    if (upper == 'EURUSD') return 'EUR/USD';
    if (upper == 'GBPUSD') return 'GBP/USD';
    if (upper == 'AUDUSD') return 'AUD/USD';
    if (upper == 'USDCAD') return 'USD/CAD';
    if (upper == 'USDJPY') return 'USD/JPY';
    if (upper == 'BTCUSD' || upper == 'BITCOIN') return 'BTC/USD';
    if (upper == 'ETHUSD' || upper == 'ETHEREUM') return 'ETH/USD';
    if (upper == 'NAS100' || upper == 'NASDAQ') return 'NAS100';
    return upper;
  }

  /// Parses raw input into a ParsedCommand.
  static ParsedCommand parse(String input) {
    final trimmed = input.trim();
    if (!trimmed.startsWith('/')) {
      return ParsedCommand.error(input, "Not a slash command");
    }

    final parts = trimmed.split(RegExp(r'\s+'));
    final rawAction = parts[0].toLowerCase();

    // Check if rawAction is a direct symbol command (e.g. /xauusd or /eurusd)
    final cleanSymbolCheck = rawAction.substring(1).toUpperCase().replaceAll('/', '');
    final isDirectSymbol = ['XAUUSD', 'EURUSD', 'GBPUSD', 'AUDUSD', 'USDCAD', 'USDJPY', 'BTCUSD', 'ETHUSD', 'NAS100'].contains(cleanSymbolCheck);

    if (!isDirectSymbol && !availableCommands.contains(rawAction)) {
      return ParsedCommand.error(input, "Unknown command: $rawAction. Type /help to see available commands.");
    }

    if (isDirectSymbol) {
      final symbol = normalizeSymbol(cleanSymbolCheck);
      double? lotSize;
      int leverage = 1;
      if (parts.length >= 2) {
        final parsed = double.tryParse(parts[1]);
        if (parsed != null) lotSize = parsed;
      }
      return ParsedCommand(
        isValid: true,
        rawCommand: input,
        action: 'long',
        symbol: symbol,
        leverage: leverage,
        value: lotSize,
      );
    }

    // Normalize buy/sell to long/short
    String action = rawAction.substring(1); // remove '/'
    if (action == 'buy') action = 'long';
    if (action == 'sell') action = 'short';


    if (action == 'help' || action == 'nuke' || action == 'bank50' || action == 'be' || action == 'breakeven' || action == 'shield') {
      return ParsedCommand(isValid: true, rawCommand: input, action: action == 'breakeven' ? 'be' : action);
    }

    if (action == 'risk' || action == 'trail') {
      double val = 2.0;
      if (parts.length >= 2) {
        final parsed = double.tryParse(parts[1].replaceAll('%', ''));
        if (parsed != null && parsed > 0) val = parsed;
      }
      return ParsedCommand(
        isValid: true,
        rawCommand: input,
        action: action,
        value: val,
        leverage: val.toInt(),
      );
    }

    if (action == 'close') {
      if (parts.length < 2) {
        return ParsedCommand(isValid: true, rawCommand: input, action: 'close', symbol: 'EUR/USD');
      }
      return ParsedCommand(
        isValid: true,
        rawCommand: input,
        action: action,
        symbol: normalizeSymbol(parts[1]),
      );
    }

    // Handle /buy, /sell, /long, /short
    if (parts.length < 2) {
      return ParsedCommand.error(input, "Usage: /$rawAction [SYMBOL] (e.g., /buy XAUUSD or /buy EUR/USD)");
    }

    String symbol = 'EUR/USD';
    double? lotSize;
    int leverage = 1;

    // Check if parts[1] is a lot size number (e.g. /buy 0.1 XAUUSD)
    final firstParamAsDouble = double.tryParse(parts[1]);
    if (firstParamAsDouble != null && parts.length >= 3) {
      lotSize = firstParamAsDouble;
      symbol = normalizeSymbol(parts[2]);
    } else {
      symbol = normalizeSymbol(parts[1]);
      if (parts.length >= 3) {
        final levStr = parts[2].replaceAll('x', '').replaceAll('X', '');
        final parsedLev = int.tryParse(levStr);
        if (parsedLev != null && parsedLev >= 1 && parsedLev <= 100) {
          leverage = parsedLev;
        } else {
          final parsedLot = double.tryParse(parts[2]);
          if (parsedLot != null) lotSize = parsedLot;
        }
      }
    }

    return ParsedCommand(
      isValid: true,
      rawCommand: input,
      action: action,
      symbol: symbol,
      leverage: leverage,
      value: lotSize,
    );
  }
}
