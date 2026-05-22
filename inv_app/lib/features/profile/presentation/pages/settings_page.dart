import 'package:flutter/material.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('系统设置')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('本地模式'),
            subtitle: const Text('切换到本地模式连接局域网设备'),
            value: false,
            onChanged: (value) {},
          ),
          SwitchListTile(
            title: const Text('深色模式'),
            value: false,
            onChanged: (value) {},
          ),
          ListTile(
            title: const Text('单位切换'),
            subtitle: const Text('kW'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
          ListTile(
            title: const Text('自定义服务器'),
            subtitle: const Text('http://localhost:8080'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
        ],
      ),
    );
  }
}
