import 'package:flutter/material.dart';
import 'package:inv_app/core/services/service_locator.dart';
import 'package:inv_app/core/services/locale_service.dart';
import 'package:inv_app/l10n/app_localizations.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final localeService = getIt<LocaleService>();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.systemSettings)),
      body: ListView(
        children: [
          SwitchListTile(
            title: Text(l10n.localMode),
            subtitle: Text(l10n.localModeDesc),
            value: false,
            onChanged: (value) {},
          ),
          SwitchListTile(
            title: Text(l10n.darkMode),
            value: false,
            onChanged: (value) {},
          ),
          ListTile(
            title: Text(l10n.unitSwitch),
            subtitle: const Text('kW'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
          ListTile(
            title: Text(l10n.customServer),
            subtitle: const Text('http://localhost:8080'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
          ListTile(
            title: Text(l10n.languageSwitch),
            subtitle: Text(localeService.currentLocale.languageCode == 'zh'
                ? '中文'
                : 'English'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showLanguageDialog(context, localeService),
          ),
        ],
      ),
    );
  }

  void _showLanguageDialog(BuildContext context, LocaleService localeService) {
    showDialog(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: Text(AppLocalizations.of(context)!.languageSwitch),
          children: [
            SimpleDialogOption(
              onPressed: () {
                localeService.switchLocale(const Locale('zh', 'CN'));
                Navigator.of(context).pop();
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('中文', style: TextStyle(fontSize: 16)),
              ),
            ),
            SimpleDialogOption(
              onPressed: () {
                localeService.switchLocale(const Locale('en', 'US'));
                Navigator.of(context).pop();
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('English', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        );
      },
    );
  }
}
