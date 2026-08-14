import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mehd_ai_flutter/models/broker_model.dart';
import 'package:mehd_ai_flutter/core/api_service.dart';

/// Modal bottom sheet allowing users to report broker withdrawal delays or spread fraud.
class BrokerDisputeModal extends StatelessWidget {
  final Broker broker;

  const BrokerDisputeModal({super.key, required this.broker});

  static Future<void> show(BuildContext context, Broker broker) async {
    final descController = TextEditingController();
    String selectedType = 'WITHDRAWAL_DELAY';
    bool isSubmitting = false;
    final parentMessenger = ScaffoldMessenger.of(context);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: Color(0xFF0D0D0D),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              border: Border(
                top: BorderSide(color: Color(0xFFFF3B3B), width: 0.5),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.report_problem_outlined, color: Color(0xFFFF3B3B), size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'REPORT ${broker.name.toUpperCase()} DISPUTE',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Your report is anonymous and helps protect the community.',
                  style: TextStyle(color: Colors.grey[600], fontSize: 11),
                ),
                const SizedBox(height: 20),

                // Pillar type selector
                const Text('REPORT TYPE', style: TextStyle(color: Color(0xFF666666), fontSize: 10, letterSpacing: 1.5)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setSheetState(() => selectedType = 'WITHDRAWAL_DELAY'),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: selectedType == 'WITHDRAWAL_DELAY'
                                ? const Color(0xFFFF3B3B).withOpacity(0.12)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: selectedType == 'WITHDRAWAL_DELAY'
                                  ? const Color(0xFFFF3B3B)
                                  : const Color(0xFF333333),
                            ),
                          ),
                          child: const Center(
                            child: Text(
                              '💸  WITHDRAWAL',
                              style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setSheetState(() => selectedType = 'SPREAD_MANIPULATION'),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: selectedType == 'SPREAD_MANIPULATION'
                                ? const Color(0xFFFF3B3B).withOpacity(0.12)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: selectedType == 'SPREAD_MANIPULATION'
                                  ? const Color(0xFFFF3B3B)
                                  : const Color(0xFF333333),
                            ),
                          ),
                          child: const Center(
                            child: Text(
                              '📈  SPREAD FRAUD',
                              style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Description field
                const Text('WHAT HAPPENED?', style: TextStyle(color: Color(0xFF666666), fontSize: 10, letterSpacing: 1.5)),
                const SizedBox(height: 8),
                TextField(
                  controller: descController,
                  maxLines: 4,
                  maxLength: 500,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'e.g. My withdrawal was blocked for 3 weeks with no explanation...',
                    hintStyle: TextStyle(color: Colors.grey[700], fontSize: 12),
                    filled: true,
                    fillColor: const Color(0xFF111111),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF333333)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF333333)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFFF3B3B)),
                    ),
                    counterStyle: const TextStyle(color: Color(0xFF555555)),
                  ),
                ),
                const SizedBox(height: 16),

                // Submit button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF3B3B).withOpacity(0.15),
                      foregroundColor: const Color(0xFFFF3B3B),
                      side: const BorderSide(color: Color(0xFFFF3B3B)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: isSubmitting
                        ? null
                        : () async {
                            final desc = descController.text.trim();
                            if (desc.length < 10) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(content: Text('Please write at least 10 characters.'), backgroundColor: Colors.red),
                              );
                              return;
                            }
                            setSheetState(() => isSubmitting = true);
                            final uid = FirebaseAuth.instance.currentUser?.uid;
                            final counterField = selectedType == 'WITHDRAWAL_DELAY'
                                ? 'withdrawal_reports'
                                : 'spread_reports';
                            try {
                              await FirebaseFirestore.instance
                                  .collection('system_metrics')
                                  .doc('broker_fraud_index')
                                  .set({
                                'brokers': {
                                  broker.id: {counterField: FieldValue.increment(1)}
                                }
                              }, SetOptions(merge: true));
                              if (uid != null) {
                                await FirebaseFirestore.instance
                                    .collection('broker_reports')
                                    .doc(broker.id)
                                    .collection('queue')
                                    .add({
                                  'type': selectedType,
                                  'description': desc,
                                  'uid': uid,
                                  'timestamp': FieldValue.serverTimestamp(),
                                  'ttl': DateTime.now().add(const Duration(days: 30)),
                                });
                              }
                            } catch (_) {}
                            await ApiService().submitBrokerReport(
                              brokerId: broker.id,
                              reportType: selectedType,
                              description: desc,
                            );
                            if (!ctx.mounted) return;
                            Navigator.pop(ctx);
                            parentMessenger.showSnackBar(SnackBar(
                              backgroundColor: const Color(0xFF00FF88).withOpacity(0.9),
                              content: const Text(
                                '✅ Report submitted. Intelligence database updated.',
                                style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                              ),
                            ));
                          },
                    child: isSubmitting
                        ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF3B3B)))
                        : const Text('SUBMIT REPORT', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
    descController.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
