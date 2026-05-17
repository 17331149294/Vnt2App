class NetworkConfig {
  String itemKey;
  String configName;
  String token;
  String deviceName;
  String virtualIPv4;
  List<String> serverList;
  List<String> udpStun;
  List<String> tcpStun;
  List<String> inIps;
  List<String> outIps;
  List<String> portMappings;
  String groupPassword;
  String deviceID;
  String virtualNetworkCardName;
  String certMode;
  int mtu;
  bool rtx;
  bool compress;
  bool fec;
  bool noPunch;
  bool noNat;
  bool noTun;
  bool allowMapping;
  int tunnelPort;
  String updatedAt;

  NetworkConfig({
    required this.itemKey,
    required this.configName,
    required this.token,
    required this.deviceName,
    required this.virtualIPv4,
    List<String>? serverList,
    List<String>? udpStun,
    List<String>? tcpStun,
    List<String>? inIps,
    List<String>? outIps,
    List<String>? portMappings,
    required this.groupPassword,
    required this.deviceID,
    required this.virtualNetworkCardName,
    this.certMode = 'skip',
    required this.mtu,
    this.rtx = false,
    this.compress = false,
    this.fec = false,
    this.noPunch = false,
    this.noNat = false,
    this.noTun = false,
    bool? allowMapping,
    this.tunnelPort = 0,
    this.updatedAt = '',
  })  : serverList = List<String>.from(serverList ?? const []),
        udpStun = List<String>.from(udpStun ?? const []),
        tcpStun = List<String>.from(tcpStun ?? const []),
        inIps = List<String>.from(inIps ?? const []),
        outIps = List<String>.from(outIps ?? const []),
        portMappings = List<String>.from(portMappings ?? const []),
        allowMapping = allowMapping ?? ((portMappings?.isNotEmpty) ?? false);

  String get primaryServerAddress {
    if (serverList.isNotEmpty) {
      return serverList.first;
    }
    return '';
  }

  String get normalizedProtocol {
    return _normalizeProtocol(primaryServerAddress);
  }

  String get effectiveCertMode {
    final normalized = certMode.trim();
    if (normalized.isEmpty) {
      return 'skip';
    }
    if (normalized == 'skip' || normalized == 'standard') {
      return normalized;
    }
    if (normalized.startsWith('finger:')) {
      return normalized;
    }
    return 'skip';
  }

  List<String> get v2CompatibleServerList {
    final source = effectiveServerList;
    if (source.isEmpty) {
      return const [];
    }
    return source
        .map(
          (address) => _normalizeServerAddress(
            address,
            fallbackProtocol: normalizedProtocol,
          ),
        )
        .toList(growable: false);
  }

  List<String> get effectiveServerList {
    if (serverList.isNotEmpty) {
      return List<String>.from(serverList);
    }
    return const [];
  }

  List<String> get effectiveUdpStun {
    return List<String>.from(udpStun);
  }

  List<String> get effectiveTcpStun {
    return List<String>.from(tcpStun);
  }

  Map<String, dynamic> toJson() {
    return {
      'itemKey': itemKey,
      'network_code': token,
      'config_name': configName,
      'ip': virtualIPv4,
      'server': effectiveServerList,
      'device_id': deviceID,
      'device_name': deviceName,
      'tun_name': virtualNetworkCardName,
      'password': groupPassword,
      'cert_mode': effectiveCertMode,
      'mtu': mtu,
      'no_punch': noPunch,
      'compress': compress,
      'rtx': rtx,
      'fec': fec,
      'input': inIps,
      'output': outIps,
      'port_mapping': portMappings,
      'no_nat': noNat,
      'no_tun': noTun,
      'allow_port_mapping': allowMapping,
      'udp_stun': effectiveUdpStun,
      'tcp_stun': effectiveTcpStun,
      'tunnel_port': tunnelPort,
      'updated_at': updatedAt,
    };
  }

  Map<String, dynamic> toJsonSimple() {
    return {
      if (configName.isNotEmpty) 'config_name': configName,
      if (token.isNotEmpty) 'network_code': token,
      if (virtualIPv4.isNotEmpty) 'ip': virtualIPv4,
      if (serverList.isNotEmpty) 'server': effectiveServerList,
      if (deviceID.isNotEmpty) 'device_id': deviceID,
      if (deviceName.isNotEmpty) 'device_name': deviceName,
      if (virtualNetworkCardName.isNotEmpty) 'tun_name': virtualNetworkCardName,
      if (groupPassword.isNotEmpty) 'password': groupPassword,
      if (certMode.isNotEmpty) 'cert_mode': effectiveCertMode,
      if (mtu != 0) 'mtu': mtu,
      if (noPunch) 'no_punch': noPunch,
      if (compress) 'compress': compress,
      if (rtx) 'rtx': rtx,
      if (fec) 'fec': fec,
      if (inIps.isNotEmpty) 'input': inIps,
      if (outIps.isNotEmpty) 'output': outIps,
      if (portMappings.isNotEmpty) 'port_mapping': portMappings,
      if (noNat) 'no_nat': noNat,
      if (noTun) 'no_tun': noTun,
      if (allowMapping) 'allow_port_mapping': allowMapping,
      if (effectiveUdpStun.isNotEmpty) 'udp_stun': effectiveUdpStun,
      if (effectiveTcpStun.isNotEmpty) 'tcp_stun': effectiveTcpStun,
      if (tunnelPort > 0) 'tunnel_port': tunnelPort,
      if (updatedAt.isNotEmpty) 'updated_at': updatedAt,
    };
  }

  factory NetworkConfig.fromJson(Map<String, dynamic> json) {
    final serverList = _stringList(json['server']);
    final portMappings = _normalizePortMappings(_stringList(json['port_mapping']));
    final allowMapping = json.containsKey('allow_port_mapping')
        ? _boolValue(json['allow_port_mapping'])
        : portMappings.isNotEmpty;
    return NetworkConfig(
      itemKey: _stringValue(json['itemKey'], fallback: ''),
      configName: _stringValue(json['config_name'], fallback: ''),
      token: _stringValue(json['network_code'], fallback: ''),
      deviceName: _stringValue(json['device_name'], fallback: ''),
      virtualIPv4: _stringValue(json['ip'], fallback: ''),
      serverList: serverList,
      udpStun: _stringList(json['udp_stun']),
      tcpStun: _stringList(json['tcp_stun']),
      inIps: _stringList(json['input']),
      outIps: _stringList(json['output']),
      portMappings: portMappings,
      groupPassword: _stringValue(json['password'], fallback: ''),
      deviceID: _stringValue(json['device_id'], fallback: ''),
      virtualNetworkCardName: _stringValue(json['tun_name'], fallback: ''),
      certMode: _stringValue(json['cert_mode'], fallback: 'skip'),
      mtu: _intValue(json['mtu'], fallback: 1410),
      rtx: _boolValue(json['rtx']),
      compress: _boolValue(json['compress']),
      fec: _boolValue(json['fec']),
      noPunch: _boolValue(json['no_punch']),
      noNat: _boolValue(json['no_nat']),
      noTun: _boolValue(json['no_tun']),
      allowMapping: allowMapping,
      tunnelPort: _intValue(json['tunnel_port']),
      updatedAt: _stringValue(json['updated_at'], fallback: ''),
    );
  }

  static String _stringValue(dynamic value, {String fallback = ''}) {
    if (value == null) {
      return fallback;
    }
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  static List<String> _stringList(dynamic value) {
    if (value is String) {
      final text = value.trim();
      return text.isEmpty ? const [] : [text];
    }
    if (value is! List) {
      return const [];
    }
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  static List<String> _normalizePortMappings(List<String> values) {
    return values.map(_normalizePortMapping).toList(growable: false);
  }

  static String _normalizePortMapping(String value) {
    final trimmed = value.trim();
    if (trimmed.contains('://')) {
      return trimmed;
    }
    final match = RegExp(r'^(tcp|udp):(.+):(\d+)-([^:]+):(\d+)$')
        .firstMatch(trimmed);
    if (match == null) {
      return trimmed;
    }
    final protocol = match.group(1)!;
    final srcHost = match.group(2)!;
    final srcPort = match.group(3)!;
    final target = match.group(4)!;
    final dstPort = match.group(5)!;
    return '$protocol://$srcHost:$srcPort-$target-$target:$dstPort';
  }

  static bool _boolValue(dynamic value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == 'true' || normalized == '1';
    }
    return false;
  }

  static int _intValue(dynamic value, {int fallback = 0}) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim()) ?? fallback;
    }
    return fallback;
  }

  static String _normalizeProtocol(String serverAddress) {
    final normalizedAddress = serverAddress.trim().toLowerCase();
    if (normalizedAddress.startsWith('quic://') ||
        normalizedAddress.startsWith('udp://')) {
      return 'QUIC';
    }
    if (normalizedAddress.startsWith('txt:')) {
      return 'DYNAMIC';
    }
    if (normalizedAddress.startsWith('tcp://')) {
      return 'TCP';
    }
    if (normalizedAddress.startsWith('wss://') ||
        normalizedAddress.startsWith('ws://')) {
      return 'WSS';
    }
    if (normalizedAddress.startsWith('dynamic://')) {
      return 'DYNAMIC';
    }
    return 'QUIC';
  }

  static String _normalizeServerAddress(
    String rawAddress, {
    required String fallbackProtocol,
  }) {
    final address = rawAddress.trim();
    if (address.isEmpty) {
      return '';
    }
    final lower = address.toLowerCase();
    if (lower.startsWith('quic://')) {
      return address;
    }
    if (lower.startsWith('txt:')) {
      return 'dynamic://${address.substring('txt:'.length)}';
    }
    if (lower.startsWith('udp://')) {
      return 'quic://${address.substring('udp://'.length)}';
    }
    if (lower.startsWith('tcp://')) {
      return address;
    }
    if (lower.startsWith('wss://')) {
      return address;
    }
    if (lower.startsWith('ws://')) {
      return 'wss://${address.substring('ws://'.length)}';
    }
    if (lower.startsWith('dynamic://')) {
      return address;
    }
    if (lower.contains('://')) {
      return address;
    }

    switch (fallbackProtocol) {
      case 'TCP':
        return 'tcp://$address';
      case 'WSS':
        return 'wss://$address';
      case 'DYNAMIC':
        return 'dynamic://$address';
      case 'QUIC':
      default:
        return 'quic://$address';
    }
  }
}
