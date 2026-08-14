import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:mehd_ai_flutter/services/language_service.dart';

class LanguageGridPicker extends StatelessWidget {
  const LanguageGridPicker({super.key});

  @override
  Widget build(BuildContext context) {
    final langService = context.watch<LanguageService>();
    
    return Container(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.language, color: MehdAiTheme.blue, size: 20),
              const SizedBox(width: 12),
              Text(
                'SELECT LANGUAGE',
                style: MehdAiTheme.headingStyle.copyWith(fontSize: 18),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'The Den speaks to every trader on earth.',
            style: MehdAiTheme.labelStyle.copyWith(
              color: MehdAiTheme.textSecondary,
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 24),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 2.0,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: LanguageService.supportedLanguages.length,
            itemBuilder: (context, index) {
              final lang = LanguageService.supportedLanguages[index];
              final code = lang['code']!;
              final isActive = langService.currentLocale.languageCode == code;
              final isEnglishOnly = code != 'en'; // Based on requirements: "English active — 7 others show coming soon"
              
              return GestureDetector(
                onTap: () {
                  if (isEnglishOnly) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${lang['name']} support coming in v2.1',
                            style: const TextStyle(fontFamily: 'JetBrains Mono')),
                        backgroundColor: MehdAiTheme.textSecondary,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  } else {
                    langService.setLocale(Locale(code));
                    Navigator.pop(context);
                  }
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: isActive ? MehdAiTheme.blue.withOpacity(0.1) : const Color(0xFF0D1117),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isActive ? MehdAiTheme.blue : MehdAiTheme.borderColor,
                    ),
                  ),
                  child: Stack(
                    children: [
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(lang['flag']!, style: const TextStyle(fontSize: 24)),
                            const SizedBox(height: 4),
                            Text(
                              lang['name']!,
                              style: MehdAiTheme.terminalStyle.copyWith(
                                fontSize: 10,
                                color: isActive ? MehdAiTheme.blue : MehdAiTheme.textPrimary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                      if (isEnglishOnly)
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: MehdAiTheme.yellow.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: Text(
                              'SOON',
                              style: MehdAiTheme.labelStyle.copyWith(fontSize: 6, color: MehdAiTheme.yellow),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class LanguageScreen extends StatelessWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MehdAiTheme.bgPrimary,
      appBar: AppBar(
        title: Text('LANGUAGE', style: MehdAiTheme.headingStyle),
        backgroundColor: MehdAiTheme.bgSecondary,
        elevation: 0,
        iconTheme: const IconThemeData(color: MehdAiTheme.white),
      ),
      body: const SingleChildScrollView(
        child: LanguageGridPicker(),
      ),
    );
  }
}
