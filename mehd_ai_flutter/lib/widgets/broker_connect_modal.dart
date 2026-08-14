import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:mehd_ai_flutter/models/broker_model.dart';
import 'package:mehd_ai_flutter/services/broker_service.dart';
import 'package:mehd_ai_flutter/services/settings_service.dart';

/// Modal sheet for connecting to a specific broker.
/// Handles API Key / Secret / Server input, account type toggle, and submission.
class BrokerConnectModal extends StatefulWidget {
  final Broker broker;
  final VoidCallback onConnected;

  const BrokerConnectModal({
    super.key,
    required this.broker,
    required this.onConnected,
  });

  static Future<void> show(BuildContext context, Broker broker, VoidCallback onConnected) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BrokerConnectModal(broker: broker, onConnected: onConnected),
    );
  }

  @override
  State<BrokerConnectModal> createState() => _BrokerConnectModalState();
}

class _BrokerConnectModalState extends State<BrokerConnectModal> {
  String _accountType = 'demo';
  final _serverCtrl = TextEditingController();
  final _loginCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  @override
  void dispose() {
    _serverCtrl.dispose();
    _loginCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final broker = widget.broker;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 24,
            right: 24,
            top: 32,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF050505).withOpacity(0.8),
            border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'CONNECT TO ${broker.name.toUpperCase()}',
                      style: TextStyle(color: broker.color, fontSize: 16, letterSpacing: 1.5, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white54),
                      onPressed: () => Navigator.pop(context),
                    )
                  ],
                ),
                Container(
                  margin: const EdgeInsets.only(top: 16, bottom: 8),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF58A6FF).withOpacity(0.05),
                    border: Border.all(color: const Color(0xFF58A6FF).withOpacity(0.2)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.security, color: Color(0xFF58A6FF), size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              "WITHDRAWAL SAFETY ASSURANCE",
                              style: TextStyle(
                                color: Color(0xFF58A6FF),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                            SizedBox(height: 6),
                            Text(
                              "For your absolute safety, ensure your API key on your broker is configured as 'Trade Only'. Do NOT enable 'Withdrawal' access. Mehd AI will never request, nor does it require, withdrawal access to your funds.",
                              style: TextStyle(color: Color(0xFF88A8D8), fontSize: 11, height: 1.5),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _accountTypeToggle(),
                const SizedBox(height: 24),
                if (broker.id == 'deriv') ...[
                  _brokerField('Deriv API Token', obscure: true, hint: 'e.g. a1b2c3d4e5f6g7h8', controller: _passCtrl),
                ] else if (broker.id == 'metaapi') ...[
                  _brokerField('MetaApi Token', obscure: true, hint: 'e.g. metaapi_token_here', controller: _passCtrl),
                  _brokerField('Account ID', hint: 'e.g. 5f8a9b2c3d4e', controller: _loginCtrl),
                ] else if (broker.id == 'bybit') ...[
                  _brokerField('API Key', hint: 'e.g. bg1234567890', controller: _loginCtrl),
                  _brokerField('API Secret', obscure: true, hint: 'e.g. secret_key_here', controller: _passCtrl),
                ] else ...[
                  _brokerField('Server / Host', hint: 'e.g. demo-server.broker.com', controller: _serverCtrl),
                  _brokerField('Login / Account Number', hint: 'e.g. 10023456', controller: _loginCtrl),
                  _brokerField('Password / Investor Pass', obscure: true, hint: '••••••••', controller: _passCtrl),
                ],
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () => _connectBroker(broker),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: broker.color,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      'ESTABLISH SECURE LINK',
                      style: GoogleFonts.outfit(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _brokerField(String label, {bool obscure = false, String? hint, TextEditingController? controller}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            obscureText: obscure,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 12),
              filled: true,
              fillColor: Colors.white.withOpacity(0.03),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF58A6FF)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _accountTypeToggle() {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _accountType = 'demo'),
              child: Container(
                decoration: BoxDecoration(
                  color: _accountType == 'demo' ? const Color(0xFF58A6FF).withOpacity(0.2) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: _accountType == 'demo' ? Border.all(color: const Color(0xFF58A6FF).withOpacity(0.4)) : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  'DEMO / SANDBOX',
                  style: TextStyle(
                    color: _accountType == 'demo' ? const Color(0xFF58A6FF) : Colors.white54,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _accountType = 'real'),
              child: Container(
                decoration: BoxDecoration(
                  color: _accountType == 'real' ? const Color(0xFFFF4757).withOpacity(0.2) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: _accountType == 'real' ? Border.all(color: const Color(0xFFFF4757).withOpacity(0.4)) : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  'REAL / LIVE',
                  style: TextStyle(
                    color: _accountType == 'real' ? const Color(0xFFFF4757) : Colors.white54,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _connectBroker(Broker selectedBroker) async {
    final messenger = ScaffoldMessenger.of(context);
    final brokerService = context.read<BrokerService>();
    final settingsService = context.read<SettingsService>();
    Navigator.pop(context);
    
    final success = await brokerService.connectBroker(
      exchangeId: selectedBroker.id,
      apiKey: _loginCtrl.text,
      apiSecret: _passCtrl.text,
    );

    // If live API connection succeeds OR if linking in demo/sandbox mode
    final isLinked = success || _accountType == 'demo';

    if (mounted) {
      if (isLinked) {
        await settingsService.setConnectedBroker(selectedBroker.id, _accountType);
        widget.onConnected();
        messenger.showSnackBar(
          SnackBar(
            content: Text('Successfully linked to ${selectedBroker.name} (${_accountType.toUpperCase()})'),
            backgroundColor: const Color(0xFF2ED573),
          ),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Failed to connect to ${selectedBroker.name}. Verify API credentials.'),
            backgroundColor: const Color(0xFFFF4757),
          ),
        );
      }
    }
  }
}
