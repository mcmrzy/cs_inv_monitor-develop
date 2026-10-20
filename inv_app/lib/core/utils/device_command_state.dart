/// Only capabilities explicitly advertised for this device enable a command.
Set<String> enabledDeviceCommands(List<dynamic> capabilities) => {
  for (final capability in capabilities)
    if (capability is Map &&
        capability['command_code'] is String &&
        (capability['command_code'] as String).isNotEmpty &&
        capability['is_enabled'] == true)
      capability['command_code'] as String,
};

bool canSendAcCommand(Set<String> commands, String command) =>
    const {'ac_on', 'ac_off'}.contains(command) && commands.contains(command);

String deviceCommandStatus(Map<String, dynamic> record) {
  final status = record['status'] as String?;
  if (const {'failed', 'timeout', 'cancelled'}.contains(status)) return status!;
  if (status == 'submitted') return status!;
  final response = record['response_data'];
  final stage = record['stage'] ?? (response is Map ? response['stage'] : null);
  return stage is String && stage.isNotEmpty ? stage : status ?? 'pending';
}

bool isSuccessfulDeviceCommand(String status) =>
    const {'success', 'applied', 'completed'}.contains(status);

bool isTerminalDeviceCommand(String status) =>
    isSuccessfulDeviceCommand(status) ||
    const {'submitted', 'failed', 'timeout', 'cancelled'}.contains(status);

String deviceCommandStatusLabel(String status) {
  if (status == 'submitted') return 'control_submitted_unconfirmed';
  if (isSuccessfulDeviceCommand(status)) return 'control_applied';
  if (const {'failed', 'timeout', 'cancelled'}.contains(status)) {
    return 'control_execution_failed';
  }
  if (const {'acknowledged', 'executing'}.contains(status)) {
    return 'control_executing';
  }
  return 'control_waiting_execution';
}
