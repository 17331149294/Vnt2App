import 'package:flutter_test/flutter_test.dart';
import 'package:vnt2_app/network_config.dart';

void main() {
  test('2.0 core config fields are read and serialized without legacy keys', () {
    final config = NetworkConfig.fromJson({
      'itemKey': 'core-1',
      'config_name': '核心配置',
      'network_code': 'game',
      'device_name': 'desktop-node',
      'tun_name': 'vnt-tun-2',
      'ip': '10.26.0.2',
      'server': ['quic://127.0.0.1:2222', 'tcp://127.0.0.1:2223'],
      'udp_stun': ['stun1.example.com'],
      'tcp_stun': ['stun2.example.com'],
      'password': 'secret',
      'cert_mode': 'skip',
      'mtu': 1410,
      'rtx': true,
      'compress': true,
      'fec': true,
      'no_punch': true,
      'no_nat': true,
      'no_tun': true,
      'input': ['10.0.0.0/24'],
      'output': ['172.16.0.0/16'],
      'port_mapping': ['tcp://0.0.0.0:8080-10.26.0.3-10.26.0.3:80'],
      'allow_port_mapping': true,
      'tunnel_port': 30000,
      'updated_at': '2026-04-30T10:00:00Z',
    });

    expect(config.token, 'game');
    expect(config.primaryServerAddress, 'quic://127.0.0.1:2222');
    expect(config.normalizedProtocol, 'QUIC');
    expect(
      config.v2CompatibleServerList,
      ['quic://127.0.0.1:2222', 'tcp://127.0.0.1:2223'],
    );
    expect(config.effectiveUdpStun, ['stun1.example.com']);
    expect(config.effectiveTcpStun, ['stun2.example.com']);
    expect(config.noNat, isTrue);
    expect(config.noPunch, isTrue);
    expect(config.compress, isTrue);

    final json = config.toJson();
    expect(json['server'], ['quic://127.0.0.1:2222', 'tcp://127.0.0.1:2223']);
    expect(json['allow_port_mapping'], isTrue);
    expect(json['tunnel_port'], 30000);
  });

  test('dynamic server addresses keep 2.0 server semantics', () {
    final config = NetworkConfig.fromJson({
      'itemKey': 'core-2',
      'config_name': '动态地址配置',
      'network_code': 'game',
      'device_name': 'desktop-node',
      'server': ['dynamic://edge.example.com'],
      'device_id': 'device-2',
      'tun_name': 'vnt-tun-2',
      'mtu': 1410,
    });

    expect(config.primaryServerAddress, 'dynamic://edge.example.com');
    expect(config.normalizedProtocol, 'DYNAMIC');
    expect(config.v2CompatibleServerList, ['dynamic://edge.example.com']);
    expect(config.effectiveCertMode, 'skip');
  });
}
