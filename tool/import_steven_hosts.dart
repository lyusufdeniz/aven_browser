import 'dart:io';

/// Build Aven adblock_hosts.txt from StevenBlack base + AdGuard DNS filter.
///
/// Usage:
///   dart run tool/import_steven_hosts.dart
///   dart run tool/import_steven_hosts.dart <steven_hosts> <adguard_filter> [out]
void main(List<String> args) {
  final steven = args.isNotEmpty
      ? args[0]
      : '${Platform.environment['TEMP']}\\steven_hosts_base.txt';
  final adguard = args.length > 1
      ? args[1]
      : '${Platform.environment['TEMP']}\\adguard_dns_filter.txt';
  final out = args.length > 2
      ? args[2]
      : 'android/app/src/main/assets/adblock_hosts.txt';

  final domains = <String>{};
  domains.addAll(parseHostsFile(File(steven)));
  if (File(adguard).existsSync()) {
    domains.addAll(parseAdguardDnsFilter(File(adguard)));
  }

  final skip = {
    'localhost',
    'localhost.localdomain',
    'local',
    'broadcasthost',
    'ip6-localhost',
    'ip6-loopback',
    '0.0.0.0',
    'dns.adguard.com',
    'dns.adguard-dns.com',
    'dns-family.adguard.com',
    'dns-family.adguard-dns.com',
  };
  domains.removeWhere(skip.contains);
  domains.removeWhere((h) => h.contains(':') || !h.contains('.'));

  final sorted = domains.toList()..sort();
  final buf = StringBuffer()
    ..writeln('# Aven Browser local block hosts')
    ..writeln('# Sources:')
    ..writeln('#   - StevenBlack/hosts (base adware/malware)')
    ..writeln('#   - AdGuard DNS filter (HostlistsRegistry filter_1)')
    ..writeln('# https://github.com/StevenBlack/hosts')
    ..writeln('# https://github.com/AdguardTeam/AdGuardSDNSFilter')
    ..writeln('# Native WebView intercept only — do not embed into page JS.')
    ..writeln('# Domains: ${sorted.length}')
    ..writeln();
  for (final d in sorted) {
    buf.writeln(d);
  }
  File(out).writeAsStringSync(buf.toString());
  stdout.writeln('Wrote ${sorted.length} domains -> $out '
      '(${File(out).lengthSync()} bytes)');
}

Set<String> parseHostsFile(File file) {
  final skip = {
    'localhost',
    'localhost.localdomain',
    'local',
    'broadcasthost',
    'ip6-localhost',
    'ip6-loopback',
    'ip6-localnet',
    'ip6-mcastprefix',
    'ip6-allnodes',
    'ip6-allrouters',
    'ip6-allhosts',
    '0.0.0.0',
  };
  final out = <String>{};
  for (final raw in file.readAsLinesSync()) {
    var line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final parts = line.split(RegExp(r'\s+'));
    if (parts.length < 2) continue;
    final host = parts[1].toLowerCase().split('%').first;
    if (host.isEmpty || skip.contains(host)) continue;
    if (host.contains(':') || !host.contains('.')) continue;
    out.add(host);
  }
  return out;
}

/// AdGuard DNS filter uses Adblock-style rules: ||domain^ and bare domain^
Set<String> parseAdguardDnsFilter(File file) {
  final out = <String>{};
  final domainRule = RegExp(
    r'^\|\|([a-z0-9][a-z0-9.-]*\.[a-z0-9.-]+)(?:\^|\$|,|$)',
    caseSensitive: false,
  );
  final bareRule = RegExp(
    r'^([a-z0-9][a-z0-9.-]*\.[a-z0-9.-]+)\^',
    caseSensitive: false,
  );
  for (final raw in file.readAsLinesSync()) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('!') || line.startsWith('[')) continue;
    if (line.startsWith('@@')) continue; // allow rules — skip for hosts set
    if (line.contains('*') || line.contains('/') || line.contains('#')) continue;
    final m = domainRule.firstMatch(line) ?? bareRule.firstMatch(line);
    if (m == null) continue;
    final host = m.group(1)!.toLowerCase();
    if (host.startsWith('.') || host.endsWith('.')) continue;
    out.add(host);
  }
  return out;
}
