#!/usr/bin/env python3
import argparse
import json
import time
import uuid
from pathlib import Path


def build_config(args: argparse.Namespace) -> dict:
    device_id = args.device_id or f"vntcapp-{uuid.uuid4()}"
    device_name = args.device_name or "vntcapp-test"
    tun_name = args.tun_name or "vnt-tun-test"
    server_list = [args.server]
    return {
        "version": "2.0",
        "export_time": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "config": {
            "itemKey": f"cfg-{int(time.time() * 1000)}",
            "config_name": args.config_name,
            "network_code": args.network_code,
            "device_id": device_id,
            "device_name": device_name,
            "tun_name": tun_name,
            "ip": "",
            "server": server_list,
            "udp_stun": [],
            "tcp_stun": [],
            "input": [],
            "output": [],
            "port_mapping": [],
            "password": args.password,
            "cert_mode": args.cert_mode,
            "mtu": args.mtu,
            "rtx": args.rtx,
            "compress": args.compress,
            "fec": args.fec,
            "no_punch": args.no_punch,
            "no_nat": args.no_nat,
            "no_tun": False,
            "allow_port_mapping": False,
            "tunnel_port": 0,
            "updated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate an importable VNT 2.0 single-config JSON file."
    )
    parser.add_argument(
        "--server",
        default="quic://115.231.35.105:2225",
        help="VNT server address with protocol prefix.",
    )
    parser.add_argument(
        "--network-code",
        default="game",
        help="Target network code. Replace if your production network uses another value.",
    )
    parser.add_argument("--password", default="", help="Optional network password.")
    parser.add_argument("--config-name", default="线上QUIC测试", help="Display name in VntcApp1.0.")
    parser.add_argument("--device-name", default="vntcapp-test", help="Logical device name.")
    parser.add_argument("--device-id", default="", help="Optional fixed device ID.")
    parser.add_argument("--tun-name", default="vnt-tun-test", help="Virtual adapter name.")
    parser.add_argument("--cert-mode", default="skip", help="Certificate mode.")
    parser.add_argument("--mtu", type=int, default=1400, help="MTU value.")
    parser.add_argument("--rtx", action="store_true", help="Enable QUIC RTX.")
    parser.add_argument("--compress", action="store_true", help="Enable LZ4 compression.")
    parser.add_argument("--fec", action="store_true", help="Enable FEC.")
    parser.add_argument("--no-punch", action="store_true", help="Disable P2P punch.")
    parser.add_argument("--no-nat", action="store_true", help="Disable built-in NAT.")
    parser.add_argument(
        "--output",
        default="testdata/import_server_115.231.35.105_2225.generated.json",
        help="Output JSON path.",
    )
    args = parser.parse_args()

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    payload = build_config(args)
    output_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"[OK] wrote {output_path}")


if __name__ == "__main__":
    main()
