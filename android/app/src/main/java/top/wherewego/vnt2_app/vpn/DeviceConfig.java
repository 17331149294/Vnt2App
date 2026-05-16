package top.wherewego.vnt2_app.vpn;

import java.util.List;

/**
 * 启动VPN的配置
 *
 * @author https://github.com/lbl8603/vnt
 */
public class DeviceConfig {
    public int virtualIp;
    public int virtualNetmask;
    public int virtualGateway;
    public int virtualNetwork;
    public int mtu;
    public List<Route> externalRoute;

    public DeviceConfig(int virtualIp, int virtualNetmask, int virtualGateway, int virtualNetwork, int mtu, List<Route> externalRoute) {
        this.virtualIp = virtualIp;
        this.virtualNetmask = virtualNetmask;
        this.virtualGateway = virtualGateway;
        this.virtualNetwork = virtualNetwork;
        this.mtu = mtu;
        this.externalRoute = externalRoute;
    }

    public static class Route {
        public int destination;
        public int netmask;

        public Route(int destination, int netmask) {
            this.destination = destination;
            this.netmask = netmask;
        }

        @Override
        public String toString() {
            return "Route{" +
                    "destination=" + destination +
                    ", netmask=" + netmask +
                    '}';
        }
    }

    @Override
    public String toString() {
        return "DeviceConfig{" +
                "virtualIp=" + virtualIp +
                ", virtualNetmask=" + virtualNetmask +
                ", virtualGateway=" + virtualGateway +
                ", virtualNetwork=" + virtualNetwork +
                ", mtu=" + mtu +
                ", externalRoute=" + externalRoute +
                '}';
    }
}

