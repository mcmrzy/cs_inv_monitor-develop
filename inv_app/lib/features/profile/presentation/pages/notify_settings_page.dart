import 'package:flutter/material.dart';

class NotifySettingsPage extends StatelessWidget {
  const NotifySettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('消息通知设置')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('推送通知'),
            subtitle: const Text('开启后可接收消息推送'),
            value: true,
            onChanged: (value) {},
          ),
          SwitchListTile(
            title: const Text('告警推送'),
            subtitle: const Text('设备告警时推送通知'),
            value: true,
            onChanged: (value) {},
          ),
          SwitchListTile(
            title: const Text('离线推送'),
            subtitle: const Text('设备离线时推送通知'),
            value: true,
            onChanged: (value) {},
          ),
          SwitchListTile(
            title: const Text('系统消息'),
            subtitle: const Text('系统公告和活动通知'),
            value: true,
            onChanged: (value) {},
          ),
          ListTile(
            title: const Text('免打扰时段'),
            subtitle: const Text('22:00 - 07:00'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
        ],
      ),
    );
  }
}
