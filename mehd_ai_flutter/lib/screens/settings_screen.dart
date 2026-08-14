import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:mehd_ai_flutter/screens/broker_screen.dart';
import 'package:mehd_ai_flutter/services/settings_service.dart';
import 'package:mehd_ai_flutter/screens/help/about_screen.dart';
import 'package:mehd_ai_flutter/screens/den/tutorial_blueprint_screen.dart';
import 'package:mehd_ai_flutter/screens/constitution_screen.dart';
import 'package:mehd_ai_flutter/screens/compliance_screen.dart';
import 'package:mehd_ai_flutter/widgets/settings_dialogs.dart';
import 'package:mehd_ai_flutter/screens/security_screen.dart';
import 'package:mehd_ai_flutter/services/payment_service.dart';


import 'package:mehd_ai_flutter/widgets/subscription_tier_modal.dart';

import 'package:mehd_ai_flutter/widgets/risk_slider_widget.dart';
import 'package:mehd_ai_flutter/widgets/settings_card_builders.dart';
import 'package:mehd_ai_flutter/widgets/settings_subscription_card.dart';
import 'package:mehd_ai_flutter/widgets/settings_danger_zone.dart';
class SettingsScreen extends StatelessWidget {
  final bool showBack;
  const SettingsScreen({super.key, this.showBack = false});


  Color _getTierColor(String tier) {
    switch (tier.toLowerCase()) {
      case 'core':
        return MehdAiTheme.blue;
      case 'precision':
        return const Color(0xFFBB00FF);
      case 'institutional':
        return MehdAiTheme.gold;
      case 'tiger':
        return const Color(0xFFFF3B3B);
      default:
        return const Color(0xFF888888);
    }
  }

  String _getTierName(String tier) {
    switch (tier.toLowerCase()) {
      case 'core':
        return 'CORE TRADER';
      case 'precision':
        return 'PRECISION TRADER';
      case 'institutional':
        return 'INSTITUTIONAL';
      case 'tiger':
        return 'TIGER MODE';
      default:
        return 'OBSERVER';
    }
  }

  String _getTierPrice(String tier) {
    switch (tier.toLowerCase()) {
      case 'core':        return '79';
      case 'precision':   return '149';
      case 'institutional': return '299';
      default:            return '0';
    }
  }

  void _showSubscriptionTierModal(BuildContext context) {
    SubscriptionTierModal.show(context);
  }


  @override
  Widget build(BuildContext context) {
    final payment = context.watch<PaymentService>();
    final tier = payment.currentTier;
    final tierColor = _getTierColor(tier);
    final tierName = _getTierName(tier);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: showBack
            ? IconButton(
                icon: Icon(Icons.arrow_back_ios_new_rounded, color: Theme.of(context).textTheme.bodyMedium?.color ?? MehdAiTheme.white, size: 18),
                onPressed: () => Navigator.pop(context),
              )
            : null,

        title: Text('SETTINGS', style: MehdAiTheme.headingStyle.copyWith(letterSpacing: 2)),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        iconTheme: IconThemeData(color: Theme.of(context).textTheme.bodyMedium?.color ?? MehdAiTheme.white),
      ),
      body: Consumer<SettingsService>(
        builder: (ctx, settings, _) => ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: [
            // Profile
            buildSettingsSectionTitle('PROFILE'),
            StreamBuilder<User?>(
              stream: FirebaseAuth.instance.authStateChanges(),
              builder: (ctx, snapshot) {
                final user = snapshot.data;
                final firebaseName = user?.displayName;
                final name = (firebaseName != null && firebaseName.isNotEmpty) 
                    ? firebaseName 
                    : (settings.profileName.isNotEmpty ? settings.profileName : 'Trader');
                final email = user?.email ?? 'Not signed in';
                final initials = name.isNotEmpty ? name[0].toUpperCase() : 'T';
                
                return Column(children: [
                  GestureDetector(
                    onTap: () => _showEditProfileDialog(context, name, settings),
                    child: Container(
                      width: 64, height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF020810),
                        border: Border.all(
                          color: tierColor.withOpacity(0.4),
                          width: 2)),
                      child: Center(
                        child: Text(initials,
                          style: TextStyle(
                            color: tierColor,
                            fontSize: 24,
                            fontWeight: FontWeight.bold)))),
                  ),
                  const SizedBox(height: 8),
                  Text(name,
                    style: const TextStyle(
                      color: Color(0xFFCCCCCC),
                      fontSize: 16,
                      fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Text(email,
                    style: const TextStyle(
                      color: Color(0xFF444444),
                      fontSize: 11)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF020810),
                      border: Border.all(
                        color: tierColor.withOpacity(0.3)),
                      borderRadius: BorderRadius.circular(20)),
                    child: Text(tierName,
                      style: TextStyle(
                        color: tierColor,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5))),
                ]);
              },
            ),
            
            const Divider(color: Color(0xFF111111), height: 32),
            
            // Trading Preferences
            buildSettingsSectionTitle('TRADING PREFERENCES'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Trading Mode', style: TextStyle(color: Color(0xFF888888), fontSize: 13)),
                      const SizedBox(height: 4),
                      Text(
                        settings.paperMode
                          ? 'Paper Trading — \$${settings.accountBalance.toStringAsFixed(0)} demo'
                          : 'Live Trading — Real money',
                        style: TextStyle(
                          color: settings.paperMode
                            ? const Color(0xFF58A6FF)
                            : const Color(0xFFFF3B3B),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Switch(
                    value: !settings.paperMode, // ON = live
                    activeColor: const Color(0xFFFF3B3B),
                    inactiveThumbColor: const Color(0xFF58A6FF),
                    onChanged: (goLive) {
                      if (goLive) {
                        _showLiveTradingWarning(context, settings);
                      } else {
                        _switchToPaper(context, settings);
                      }
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Default Lot Size', style: TextStyle(color: Color(0xFFDDDDDD), fontSize: 13)),
                      Text('${settings.defaultLotSize.toStringAsFixed(2)} Lots', style: const TextStyle(color: Color(0xFF58A6FF), fontSize: 13, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text('Set default trade size. Enable growth by adjusting target exposure.', style: TextStyle(color: Color(0xFF666666), fontSize: 11)),
                  SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: const Color(0xFF58A6FF),
                      inactiveTrackColor: const Color(0xFF111111),
                      thumbColor: const Color(0xFF58A6FF),
                      overlayColor: const Color(0xFF58A6FF).withOpacity(0.2),
                      trackHeight: 4.0,
                    ),
                    child: Slider(
                      // Clamp prevents crash if stored value is outside slider bounds
                      value: settings.defaultLotSize.clamp(0.01, 10.0),
                      min: 0.01,
                      max: 10.0,
                      divisions: 999, // 0.01 increments
                      onChanged: (v) => settings.setDefaultLotSize(v, save: false),
                      onChangeEnd: (v) => settings.setDefaultLotSize(v, save: true),
                    ),
                  ),
                ],
              ),
            ),
            SwitchListTile(
              title: const Text('Auto Stop-Loss', style: TextStyle(color: Color(0xFFDDDDDD), fontSize: 13)),
              subtitle: const Text('Den sets SL automatically', style: TextStyle(color: Color(0xFF666666), fontSize: 11)),
              value: settings.autoStopLoss,
              secondary: const Icon(Icons.shield_outlined, color: Color(0xFF888888)),
              activeColor: const Color(0xFF58A6FF),
              inactiveThumbColor: const Color(0xFF444444),
              inactiveTrackColor: const Color(0xFF111111),
              onChanged: settings.setAutoStopLoss,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Minimum Conviction Threshold', style: TextStyle(color: Color(0xFFDDDDDD), fontSize: 13)),
                      Text('${settings.convictionThreshold.toInt()}%', style: const TextStyle(color: Color(0xFF58A6FF), fontSize: 13, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    settings.convictionThreshold > 90
                        ? '🎯 Ultra-High Precision — Trades will be rare & highly selective'
                        : settings.convictionThreshold < 65
                            ? '⚡ High Frequency — More trade triggers, higher volatility exposure'
                            : 'Agent consensus required to broadcast trade',
                    style: TextStyle(
                      color: settings.convictionThreshold > 90
                          ? const Color(0xFF58A6FF)
                          : settings.convictionThreshold < 65
                              ? const Color(0xFFD29922)
                              : const Color(0xFF666666),
                      fontSize: 11,
                    ),
                  ),
                  SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: const Color(0xFF58A6FF),
                      inactiveTrackColor: const Color(0xFF111111),
                      thumbColor: const Color(0xFF58A6FF),
                      overlayColor: const Color(0xFF58A6FF).withOpacity(0.2),
                      trackHeight: 4.0,
                    ),
                    child: Slider(
                      value: settings.convictionThreshold,
                      min: 50,
                      max: 100,
                      divisions: 50,
                      onChanged: (v) => settings.setConvictionThreshold(v, save: false),
                      onChangeEnd: (v) => settings.setConvictionThreshold(v, save: true),
                    ),
                  ),
                ],
              ),
            ),
            
            const Divider(color: Color(0xFF111111), height: 32),
            
            buildSettingsSectionTitle('RISK MANAGEMENT'),
            GlobalRiskSlider(settings: settings),

            const Divider(color: Color(0xFF111111), height: 32),
            
            // Notifications
            buildSettingsSectionTitle('NOTIFICATIONS'),
            SwitchListTile(
              title: const Text('Trade Signals', style: TextStyle(color: Color(0xFFDDDDDD), fontSize: 13)),
              subtitle: const Text('Notifications when Den finds setup', style: TextStyle(color: Color(0xFF666666), fontSize: 11)),
              value: settings.tradeSignals,
              secondary: const Icon(Icons.notifications_active_outlined, color: Color(0xFF888888)),
              activeColor: const Color(0xFF58A6FF),
              inactiveThumbColor: const Color(0xFF444444),
              inactiveTrackColor: const Color(0xFF111111),
              onChanged: settings.setTradeSignals,
            ),
            SwitchListTile(
              title: const Text('Guardian Alerts', style: TextStyle(color: Color(0xFFDDDDDD), fontSize: 13)),
              value: settings.guardianAlerts,
              secondary: const Icon(Icons.admin_panel_settings_outlined, color: Color(0xFF888888)),
              activeColor: const Color(0xFF58A6FF),
              inactiveThumbColor: const Color(0xFF444444),
              inactiveTrackColor: const Color(0xFF111111),
              onChanged: settings.setGuardianAlerts,
            ),
            
            const Divider(color: Color(0xFF111111), height: 32),
            
            // Subscription & Billing
            buildSettingsSectionTitle('SUBSCRIPTION & BILLING'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SettingsSubscriptionCard(
                getTierColor: _getTierColor,
                getTierName: _getTierName,
                getTierPrice: _getTierPrice,
                build3DCard: build3DSettingsCard,
                onManageTap: () => _showSubscriptionTierModal(context),
              ),
            ),

            const Divider(color: Color(0xFF111111), height: 32),

            // Broker Connection
            buildSettingsSectionTitle('BROKER CONNECTION'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  build3DSettingsCard(
                    context,
                    'Connect Broker',
                    'Manage your API integrations',
                    Icons.account_balance_rounded,
                    const [Color(0xFF142840), Color(0xFF0B1825)],
                    MehdAiTheme.blue,
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BrokerScreen())),
                  ),
                  const SizedBox(height: 12),
                  build3DSettingsCard(
                    context,
                    'Security Promise & Manifesto',
                    'Unbreakable anti-broker defenses',
                    Icons.security_rounded,
                    const [Color(0xFF0F2C24), Color(0xFF071B16)],
                    const Color(0xFF00FF88),
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SecurityScreen(showBack: true))),
                  ),
                ],
              ),
            ),
            
            const Divider(color: Color(0xFF111111), height: 32),
            
            // Interface
            buildSettingsSectionTitle('INTERFACE PREFERENCES'),
            SwitchListTile(
              title: const Text('Show Agent Names', style: TextStyle(color: Color(0xFF888888), fontSize: 13)),
              subtitle: const Text('Shows DON, ORACLE etc. in terminal', style: TextStyle(color: Color(0xFF444444), fontSize: 10)),
              value: settings.showAgentNames,
              secondary: const Icon(Icons.visibility_outlined, color: Color(0xFF888888)),
              activeColor: const Color(0xFF58A6FF),
              onChanged: settings.setShowAgentNames,
            ),
            SwitchListTile(
              title: const Text('Sandbox Mode', style: TextStyle(color: Color(0xFF888888), fontSize: 13)),
              subtitle: const Text('Your trades invisible to others', style: TextStyle(color: Color(0xFF444444), fontSize: 10)),
              value: settings.sandboxMode,
              secondary: const Icon(Icons.nightlight_outlined, color: Color(0xFF888888)),
              activeColor: const Color(0xFF58A6FF),
              onChanged: settings.setSandboxMode,
            ),

            const Divider(color: Color(0xFF111111), height: 32),

            // About
            buildSettingsSectionTitle('ABOUT'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: build3DSettingsCard(
                context,
                'About Mehd AI',
                'v1.0.0 — The Den',
                Icons.info_rounded,
                const [Color(0xFF1A2030), Color(0xFF0F1520)],
                Colors.white70,
                () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutScreen())),
              ),
            ),

            const Divider(color: Color(0xFF111111), height: 32),

            // Tutorial & Legal
            buildSettingsSectionTitle('TUTORIALS & LEGAL'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: build3DSettingsCard(
                        context,
                        'Tutorial\nBlueprint',
                        'CyberSpace walkthrough',
                        Icons.school_rounded,
                        const [Color(0xFF0A2040), Color(0xFF051020)],
                        const Color(0xFF00D1FF),
                        () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TutorialBlueprintScreen())),
                      )),
                      const SizedBox(width: 12),
                      Expanded(child: build3DSettingsCard(
                        context,
                        'Holy Trinity\nConstitution',
                        'The Den\'s laws',
                        Icons.menu_book_rounded,
                        const [Color(0xFF1A2A3A), Color(0xFF0D1520)],
                        MehdAiTheme.blue,
                        () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ConstitutionScreen())),
                      )),
                    ],
                  ),
                  const SizedBox(height: 12),
                  build3DSettingsCard(
                    context,
                    'Compliance & Risk Protocol',
                    'Institutional safety standards',
                    Icons.gavel_rounded,
                    const [Color(0xFF2A2A1A), Color(0xFF15150D)],
                    const Color(0xFFD29922),
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ComplianceScreen())),
                  ),
                ],
              ),
            ),

            const Divider(color: Color(0xFF111111), height: 32),

            SettingsDangerZone(settings: settings),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  void _showEditProfileDialog(BuildContext context, String currentName, SettingsService settings) =>
      showEditProfileDialog(context, currentName, settings);

  void _showLiveTradingWarning(BuildContext context, SettingsService settings) =>
      showLiveTradingWarning(context, settings);

  // ignore: unused_element
  void _switchToLive(BuildContext context, SettingsService settings) =>
      switchToLive(context, settings);

  void _switchToPaper(BuildContext context, SettingsService settings) =>
      switchToPaper(context, settings);
}

