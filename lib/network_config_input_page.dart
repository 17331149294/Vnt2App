import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'data_persistence.dart';
import 'network_config.dart';
import 'dart:io';
import 'widgets/custom_tooltip_text_field.dart';
import 'utils/ip_utils.dart';
import 'utils/toast_utils.dart';
import 'utils/responsive_utils.dart';
import 'theme/app_theme.dart';

class NetworkConfigInputPage extends StatefulWidget {
  final NetworkConfig? config;

  const NetworkConfigInputPage({super.key, this.config});
  @override
  _NetworkConfigInputPageState createState() => _NetworkConfigInputPageState();
}

class _NetworkConfigInputPageState extends State<NetworkConfigInputPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _groupNumberController = TextEditingController();
  final _deviceNameController = TextEditingController(
      text: () {
        String version = Platform.operatingSystemVersion.replaceAll('"', '').trim();
        return version.length > 64 ? version.substring(0, 64) : version;
      }());
  final _virtualIPv4Controller = TextEditingController();
  final _serverAddressControllers = <TextEditingController>[];
  final _serverProtocolSelections = <String>[];
  final _udpStunServers = <TextEditingController>[];
  final _tcpStunServers = <TextEditingController>[];
  final _inIps = <TextEditingController>[];
  final _outIps = <TextEditingController>[];
  final _portMappings = <TextEditingController>[];
  final _groupPasswordController = TextEditingController();
  final _deviceIDController = TextEditingController(); // 不可编辑
  final _virtualNetworkCardNameController = TextEditingController();
  final _mtuController = TextEditingController();
  final _certModeController = TextEditingController(text: 'skip');
  final _tunnelPortController = TextEditingController();

  bool _isPasswordVisible = false;
  bool _isTokenVisible = false;
  String _communicationMethod = 'QUIC';
  String _builtInIpProxy = 'OPEN';
  String _p2pPunch = 'OPEN';
  bool _isMoreParametersVisible = false;
  bool _rtx = false;
  bool _fec = false;
  bool _noTun = false;
  bool _allowPortMapping = false;

  String _compressionMethod = 'none'; // 核心仅支持 none/lz4

  _NetworkConfigInputPageState() {}

  @override
  void initState() {
    super.initState();
    getDeviceUniqueId();
    if (widget.config != null) {
      _loadConfig(widget.config!);
    } else {
      _loadDefault();
    }
    if (_udpStunServers.isEmpty) {
      _udpStunServers.add(TextEditingController());
    }
    if (_tcpStunServers.isEmpty) {
      _tcpStunServers.add(TextEditingController());
    }
    if (_inIps.isEmpty) {
      _inIps.add(TextEditingController());
    }
    if (_outIps.isEmpty) {
      _outIps.add(TextEditingController());
    }
    if (_serverAddressControllers.isEmpty) {
      _addServerAddressController();
    }
    if (_portMappings.isEmpty) {
      _portMappings.add(TextEditingController());
    }
  }

  void _loadDefault() {
    _udpStunServers.add(TextEditingController(text: "stun.miwifi.com:3478"));
    _udpStunServers.add(TextEditingController(text: "stun.chat.bilibili.com:3478"));
    _udpStunServers.add(TextEditingController(text: "stun.l.google.com:19302"));
    _mtuController.text = "1410";
    _addServerAddressController(
      text: "47.107.166.63:29872",
      protocol: 'TCP',
      updateState: false,
    );
  }

  void _loadConfig(NetworkConfig config) {
    _nameController.text = config.configName;
    _groupNumberController.text = config.token;
    _deviceNameController.text = config.deviceName;
    _virtualIPv4Controller.text = config.virtualIPv4;
    for (final serverAddress in config.effectiveServerList) {
      _addServerAddressController(
        text: stripScheme(serverAddress),
        protocol: normalizeCommunicationMethod(serverAddress),
        updateState: false,
      );
    }
    for (String stunServer in config.effectiveUdpStun) {
      _udpStunServers.add(TextEditingController(text: stunServer));
    }
    for (String stunServer in config.tcpStun) {
      _tcpStunServers.add(TextEditingController(text: stunServer));
    }
    for (String inIp in config.inIps) {
      _inIps.add(TextEditingController(text: inIp));
    }
    for (String outIp in config.outIps) {
      _outIps.add(TextEditingController(text: outIp));
    }
    for (String portMapping in config.portMappings) {
      _portMappings.add(TextEditingController(text: portMapping));
    }
    _groupPasswordController.text = config.groupPassword;
    _communicationMethod = normalizeCommunicationMethod(
      config.effectiveServerList.isNotEmpty
          ? config.effectiveServerList.first
          : '',
    );
    _deviceIDController.text = config.deviceID;
    _virtualNetworkCardNameController.text = config.virtualNetworkCardName;
    _mtuController.text = config.mtu.toString();
    _certModeController.text = config.effectiveCertMode;
    _tunnelPortController.text =
        config.tunnelPort > 0 ? config.tunnelPort.toString() : '';
    _p2pPunch = config.noPunch ? 'CLOSE' : 'OPEN';
    _compressionMethod = config.compress ? 'lz4' : 'none';
    _rtx = config.rtx;
    _fec = config.fec;
    _noTun = config.noTun;
    _allowPortMapping = config.allowMapping;
    setState(() {
      _builtInIpProxy = config.noNat ? 'CLOSE' : 'OPEN';
    });
  }

  Future<void> getDeviceUniqueId() async {
    String uniqueId = await DataPersistence().loadUniqueId();
    setState(() {
      _deviceIDController.text = uniqueId;
    });
  }

  void _submitForm() {
    if (_formKey.currentState!.validate()) {
      var name = _nameController.text.trim();
      var groupNumber = _groupNumberController.text.trim();
      if (name.isEmpty) {
        if (groupNumber.length > 6) {
          name = groupNumber.substring(0, 6);
        } else {
          name = groupNumber;
        }
      }
      final serverList = <String>[];
      for (var i = 0; i < _serverAddressControllers.length; i++) {
        final body = _serverAddressControllers[i].text.trim();
        if (body.isEmpty) {
          continue;
        }
        serverList.add(_applyServerScheme(body, _serverProtocolAt(i)));
      }
      if (serverList.isEmpty) {
        showTopToast(context, '请至少填写一个服务器地址', isSuccess: false);
        return;
      }
      final portMappings = _portMappings
          .map((controller) => controller.text)
          .where((text) => text.isNotEmpty)
          .toList();
      NetworkConfig config = NetworkConfig(
        itemKey: widget.config?.itemKey ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        configName: name,
        token: _groupNumberController.text,
        deviceName: _deviceNameController.text,
        virtualIPv4: _virtualIPv4Controller.text,
        serverList: serverList,
        udpStun: _udpStunServers
            .map((controller) => controller.text)
            .where((text) => text.isNotEmpty)
            .toList(),
        tcpStun: _tcpStunServers
            .map((controller) => controller.text)
            .where((text) => text.isNotEmpty)
            .toList(),
        inIps: _inIps
            .map((controller) => controller.text)
            .where((text) => text.isNotEmpty)
            .toList(),
        outIps: _outIps
            .map((controller) => controller.text)
            .where((text) => text.isNotEmpty)
            .toList(),
        portMappings: portMappings,
        groupPassword: _groupPasswordController.text,
        deviceID: _deviceIDController.text,
        virtualNetworkCardName: _virtualNetworkCardNameController.text,
        certMode: _certModeController.text.trim().isEmpty
            ? 'skip'
            : _certModeController.text.trim(),
        mtu: int.tryParse(_mtuController.text) ?? 1410,
        noNat: _builtInIpProxy == 'CLOSE',
        noPunch: _p2pPunch == 'CLOSE',
        compress: _compressionMethod == 'lz4',
        rtx: _rtx,
        fec: _fec,
        noTun: _noTun,
        allowMapping: _allowPortMapping,
        tunnelPort: int.tryParse(_tunnelPortController.text.trim()) ?? 0,
      );
      Navigator.pop(context, config);
    } else {
      showTopToast(context, '参数校验失败,请检查标红参数', isSuccess: false);
    }
  }

  void _addController(List<TextEditingController> controllers) {
    setState(() {
      controllers.add(TextEditingController());
    });
  }

  void _removeController(int index, List<TextEditingController> controllers) {
    if (controllers.length > 1) {
      setState(() {
        controllers.removeAt(index);
      });
    }
  }

  String _serverProtocolAt(int index) {
    if (index < _serverProtocolSelections.length) {
      return _serverProtocolSelections[index];
    }
    return _communicationMethod;
  }

  void _addServerAddressController({
    String text = '',
    String protocol = 'TCP',
    bool updateState = true,
  }) {
    void add() {
      _serverAddressControllers.add(TextEditingController(text: text));
      _serverProtocolSelections.add(protocol);
    }

    if (updateState) {
      setState(add);
    } else {
      add();
    }
  }

  void _removeServerAddressController(int index) {
    if (_serverAddressControllers.length <= 1) {
      return;
    }
    setState(() {
      _serverAddressControllers.removeAt(index);
      if (index < _serverProtocolSelections.length) {
        _serverProtocolSelections.removeAt(index);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 设置状态栏颜色以适配当前主题
    if (Platform.isAndroid || Platform.isIOS) {
      SystemChrome.setSystemUIOverlayStyle(
        SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          '组网参数配置',
          style: TextStyle(
            color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        ),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                primaryColor.withOpacity(0.15),
                primaryColor.withOpacity(0.05),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        iconTheme: IconThemeData(
          color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
        ),
        actions: [
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Tooltip(
                  message: '保存',
                  child: IconButton(
                    icon: Icon(
                      Icons.save,
                      color: primaryColor,
                    ),
                    onPressed: _submitForm,
                  ))),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                CustomTooltipTextField(
                  controller: _nameController,
                  labelText: '配置名称',
                  tooltipMessage: '(方便在首页区分不同的组网配置选项，可填任意字符)',
                  maxLength: 10,
                ),
                const SizedBox(height: 20),
                _buildSectionTitle('基本参数'),
                CustomTooltipTextField(
                  controller: _groupNumberController,
                  labelText: '组网token',
                  tooltipMessage: '(相同的token和服务器才能组建一个虚拟局域网)',
                  maxLength: 64,
                  obscureText: !_isTokenVisible, // 控制是否隐藏文本
                  suffixIcon: IconButton( // 可见性切换按钮
                    icon: Icon(
                      _isTokenVisible ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () {
                      setState(() {
                        _isTokenVisible = !_isTokenVisible;
                      });
                    },
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '请输入token';
                    }
                    return null;
                  },
                ),
                _buildTextFormField(
                  _deviceNameController,
                  '设备名称',
                  64,
                  (value) {
                    if (value == null || value.isEmpty) {
                      return '请输入设备名称';
                    }
                    return null;
                  },
                ),
                CustomTooltipTextField(
                  controller: _virtualIPv4Controller,
                  labelText: '虚拟IPv4',
                  tooltipMessage: '(不输入则由VNTS分配虚拟IPv4)',
                  maxLength: 15,
                  validator: (value) {
                    final regex = RegExp(
                      r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$',
                    );
                    if (value != null &&
                        value.isNotEmpty &&
                        !regex.hasMatch(value)) {
                      return '请输入有效的 IPv4 地址';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                _buildServerAddressFields(),
                const SizedBox(height: 20),
                _buildDropdownField(
                  '压缩',
                  ['none', 'lz4'],
                  _compressionMethod,
                  (value) {
                    setState(() {
                      _compressionMethod = value!;
                    });
                  },
                ),
                _buildSectionTitle('子网代理&端口映射'),
                _buildDynamicTooltipFields(
                  'in-ip 对端路由',
                  _inIps,
                  '例如想要通过10.26.0.10去访问对端192.168.0.*网段内其他设备则填：192.168.0.1/24,10.26.0.10',
                  34,
                  IpUtils.parseInIpString,
                ),
                _buildDynamicTooltipFields(
                  'out-ip 本机网段',
                  _outIps,
                  '本地网段，示例：0.0.0.0/0 或 192.168.2.0/24',
                  18,
                  IpUtils.parseOutIpString,
                ),
                _buildDynamicTooltipFields(
                  '端口映射',
                  _portMappings,
                  '核心格式：tcp://0.0.0.0:80-10.26.0.10-10.26.0.10:80',
                  72,
                  (value) {
                    final regex = RegExp(
                        r'^(tcp|udp)://[^-]+:(\d{1,5})-\d{1,3}(?:\.\d{1,3}){3}-.+:(\d{1,5})$');
                    final match = regex.firstMatch(value);

                    if (match != null) {
                      final int port1 = int.parse(match.group(2)!);
                      final int port2 = int.parse(match.group(3)!);

                      if ((port1 >= 1 && port1 <= 65535) &&
                          (port2 >= 1 && port2 <= 65535)) {
                        return null;
                      }
                      throw const FormatException("端口取值1~65535");
                    }
                    throw const FormatException("格式错误");
                  },
                ),
                const SizedBox(height: 20),
                _buildSectionTitle('传输安全'),
                _buildTextFormField(
                  _groupPasswordController,
                  '组网密码',
                  256,
                  null,
                  null,
                  true,
                  !_isPasswordVisible,
                  IconButton(
                    icon: Icon(
                      _isPasswordVisible
                          ? Icons.visibility
                          : Icons.visibility_off,
                    ),
                    onPressed: () {
                      setState(() {
                        _isPasswordVisible = !_isPasswordVisible;
                      });
                    },
                  ),
                ),
                const SizedBox(height: 20),
                _buildSectionTitle('更多参数'),
                Visibility(
                  visible: _isMoreParametersVisible,
                  child: Column(
                    children: [
                      _buildTextFormField(
                        _deviceIDController,
                        '设备ID',
                        null,
                        null,
                        null,
                        false,
                      ),
                      const SizedBox(height: 16),
                      _buildTextFormField(
                        _virtualNetworkCardNameController,
                        '虚拟网卡名称',
                        10,
                      ),
                      const SizedBox(height: 16),
                      _buildTextFormField(
                        _mtuController,
                        '虚拟网卡mtu',
                        null,
                        (value) {
                          if (value == null || value.isEmpty) {
                            return null;
                          }
                          final n = num.tryParse(value);
                          if (n == null || n <= 0) {
                            return '请输入有效的正整数';
                          }
                          return null;
                        },
                        TextInputType.number,
                      ),
                      const SizedBox(height: 16),
                      _buildTextFormField(
                        _certModeController,
                        '证书验证',
                        80,
                        (value) {
                          final text = value?.trim() ?? '';
                          if (text.isEmpty ||
                              text == 'skip' ||
                              text == 'standard' ||
                              RegExp(r'^finger:[0-9a-fA-F]{64}$')
                                  .hasMatch(text)) {
                            return null;
                          }
                          return '请输入 skip、standard 或 finger:<64位hex>';
                        },
                        null,
                        true,
                        false,
                        null,
                        'skip：跳过证书校验；standard：使用系统证书校验；finger:<64位hex>：校验指定证书指纹',
                      ),
                      const SizedBox(height: 16),
                      _buildTextFormField(
                        _tunnelPortController,
                        'P2P 直连端口（可选）',
                        null,
                        (value) {
                          final text = value?.trim() ?? '';
                          if (text.isEmpty) {
                            return null;
                          }
                          final port = int.tryParse(text);
                          if (port == null || port < 1 || port > 65535) {
                            return '端口取值1~65535';
                          }
                          return null;
                        },
                        TextInputType.number,
                        true,
                        false,
                        null,
                        '留空自动分配；需要固定本机直连端口时填写 1~65535',
                      ),
                      const SizedBox(height: 16),
                      _buildRadioGroup(
                        '无TUN模式',
                        [('开启', 'OPEN'), ('关闭', 'CLOSE')],
                        _noTun ? 'OPEN' : 'CLOSE',
                        (value) {
                          setState(() {
                            _noTun = value == 'OPEN';
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      _buildRadioGroup(
                        'QUIC优化传输',
                        [('开启', 'OPEN'), ('关闭', 'CLOSE')],
                        _rtx ? 'OPEN' : 'CLOSE',
                        (value) {
                          setState(() {
                            _rtx = value == 'OPEN';
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      _buildRadioGroup(
                        'FEC前向纠错',
                        [('开启', 'OPEN'), ('关闭', 'CLOSE')],
                        _fec ? 'OPEN' : 'CLOSE',
                        (value) {
                          setState(() {
                            _fec = value == 'OPEN';
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      _buildRadioGroup(
                        '端口映射',
                        [('开启', 'OPEN'), ('关闭', 'CLOSE')],
                        _allowPortMapping ? 'OPEN' : 'CLOSE',
                        (value) {
                          setState(() {
                            _allowPortMapping = value == 'OPEN';
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      _buildRadioGroup(
                        'P2P 打洞',
                        [('开启', 'OPEN'), ('关闭，仅中继', 'CLOSE')],
                        _p2pPunch,
                        (value) {
                          setState(() {
                            _p2pPunch = value!;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      _buildRadioGroup(
                        '内置IP代理',
                        [('开启', 'OPEN'), ('关闭', 'CLOSE')],
                        _builtInIpProxy,
                        (value) {
                          setState(() {
                            _builtInIpProxy = value!;
                          });
                        },
                      ),
                      const SizedBox(height: 24),
                      _buildDynamicFields(
                        'UDP STUN服务器',
                        _udpStunServers,
                        _addController,
                        _removeController,
                      ),
                      _buildDynamicFields(
                        'TCP STUN服务器',
                        _tcpStunServers,
                        _addController,
                        _removeController,
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _isMoreParametersVisible = !_isMoreParametersVisible;
                    });
                  },
                  child: Text(_isMoreParametersVisible ? '隐藏更多参数' : '显示更多参数'),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextFormField(
    TextEditingController controller,
    String labelText,
    int? maxLength, [
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    bool enabled = true,
    bool obscureText = false,
    Widget? suffixIcon,
    String? helperText,
  ]) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: labelText,
        suffixIcon: suffixIcon,
        helperText: helperText,
        helperMaxLines: 4,
      ),
      maxLength: maxLength,
      validator: validator,
      keyboardType: keyboardType,
      enabled: enabled,
      obscureText: obscureText,
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(fontSize: context.fontMedium, fontWeight: FontWeight.bold),
    );
  }

  Widget _buildRadioGroup(
    String title,
    List<(String, String)> list,
    String groupValue,
    ValueChanged<String?> onChanged,
  ) {
    // 获取屏幕宽度，判断是否为竖屏或窄屏设备
    final screenWidth = MediaQuery.of(context).size.width;
    final isNarrowScreen = screenWidth < 600;

    // 竖屏或窄屏设备使用Column布局，宽屏设备使用Row布局
    if (isNarrowScreen) {
      return Padding(
        padding: const EdgeInsets.only(top: 12.0, bottom: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Text(
                title,
                style: TextStyle(fontWeight: FontWeight.w500),
                textAlign: TextAlign.left,
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                alignment: WrapAlignment.start,
                crossAxisAlignment: WrapCrossAlignment.start,
                spacing: 4,
                runSpacing: 4,
                children: list.map(((String, String) x) {
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Radio<String>(
                        value: x.$2,
                        groupValue: groupValue,
                        onChanged: onChanged,
                        visualDensity: VisualDensity.compact,
                      ),
                      Flexible(
                        child: Text(
                          x.$1,
                          style: TextStyle(fontSize: context.fontSmall),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      );
    }

    // 宽屏设备使用原有的Row布局
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12.0),
          child: Text(title),
        ),
        Expanded(
          child: Wrap(
            spacing: 4,
            runSpacing: 0,
            children: list.map(((String, String) x) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Radio<String>(
                    value: x.$2,
                    groupValue: groupValue,
                    onChanged: onChanged,
                  ),
                  Text(x.$1),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildCheckboxField(
    String title,
    bool value,
    ValueChanged<bool?> onChanged,
  ) {
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(title),
      value: value,
      onChanged: onChanged,
      controlAffinity: ListTileControlAffinity.leading,
    );
  }

  Widget _buildDynamicFields(
    String label,
    List<TextEditingController> controllers,
    Function(List<TextEditingController>) addController,
    Function(int, List<TextEditingController>) removeController, {
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    int maxLength = 64,
  }) {
    return Column(
      children: [
        ...controllers.asMap().entries.map((entry) {
          int index = entry.key;
          TextEditingController controller = entry.value;
          return Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: controller,
                  decoration: InputDecoration(
                      labelText: '$label${index == 0 ? '' : ' ---$index'}'),
                  maxLength: maxLength,
                  keyboardType: keyboardType,
                  validator: validator,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.remove_circle),
                onPressed: () => removeController(index, controllers),
              ),
            ],
          );
        }).toList(),
        Row(
          children: [
            Expanded(child: Container()),
            IconButton(
              icon: const Icon(Icons.add_circle),
              onPressed: () => addController(controllers),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDynamicTooltipFields(
    String label,
    List<TextEditingController> controllers,
    String tooltipMessage,
    int maxLength,
    Function(String) parser,
  ) {
    return Column(
      children: [
        ...controllers.asMap().entries.map((entry) {
          int index = entry.key;
          TextEditingController controller = entry.value;
          return Row(
            children: [
              Expanded(
                child: CustomTooltipTextField(
                  controller: controller,
                  labelText: '$label${index == 0 ? '' : ' ---$index'}',
                  tooltipMessage: tooltipMessage,
                  maxLength: maxLength,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return null;
                    }
                    try {
                      parser(value);
                    } catch (e) {
                      return e.toString();
                    }
                    return null;
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.remove_circle),
                onPressed: () => _removeController(index, controllers),
              ),
            ],
          );
        }).toList(),
        Row(
          children: [
            Expanded(child: Container()),
            IconButton(
              icon: const Icon(Icons.add_circle),
              onPressed: () => _addController(controllers),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildServerAddressFields() {
    const protocols = ['TCP', 'QUIC', 'WSS', 'DYNAMIC'];
    final isNarrowScreen = MediaQuery.of(context).size.width < 600;
    return Column(
      children: [
        ..._serverAddressControllers.asMap().entries.map((entry) {
          final index = entry.key;
          final controller = entry.value;
          final protocolDropdown = DropdownButtonFormField<String>(
            value: _serverProtocolAt(index),
            decoration: const InputDecoration(labelText: '协议'),
            isExpanded: true,
            items: protocols.map((protocol) {
              return DropdownMenuItem(
                value: protocol,
                child: Text(protocol.toLowerCase()),
              );
            }).toList(),
            onChanged: (value) {
              if (value == null) {
                return;
              }
              setState(() {
                while (_serverProtocolSelections.length <= index) {
                  _serverProtocolSelections.add(_communicationMethod);
                }
                _serverProtocolSelections[index] = value;
                if (index == 0) {
                  _communicationMethod = value;
                }
              });
            },
          );
          final addressField = CustomTooltipTextField(
            controller: controller,
            labelText: '服务器地址${index == 0 ? '' : ' ---$index'}',
            tooltipMessage:
                '支持多个 VNTS 2.0 地址；协议从左侧选择，地址填写 host:port 或 txt:domain',
            maxLength: 96,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return null;
              }
              final error = _validateServerAddress(value);
              return error == null ? null : FormatException(error).toString();
            },
          );
          if (isNarrowScreen) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 118, child: protocolDropdown),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.remove_circle),
                        onPressed: () => _removeServerAddressController(index),
                      ),
                    ],
                  ),
                  addressField,
                ],
              ),
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 116,
                child: protocolDropdown,
              ),
              const SizedBox(width: 8),
              Expanded(child: addressField),
              IconButton(
                icon: const Icon(Icons.remove_circle),
                onPressed: () => _removeServerAddressController(index),
              ),
            ],
          );
        }).toList(),
        Row(
          children: [
            Expanded(child: Container()),
            IconButton(
              icon: const Icon(Icons.add_circle),
              onPressed: () => _addServerAddressController(),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDropdownField(
    String labelText,
    List<String> items,
    String value,
    ValueChanged<String?> onChanged,
  ) {
    return DropdownButtonFormField(
      value: value,
      decoration: InputDecoration(labelText: labelText),
      isExpanded: true, // 让下拉框内容自适应宽度，防止超出窗口
      items: items.map((String item) {
        return DropdownMenuItem(
          value: item,
          child: Text(item),
        );
      }).toList(),
      onChanged: onChanged,
    );
  }

}

String? stripPrefix(String input, String prefix) {
  if (input.startsWith(prefix)) {
    return input.substring(prefix.length);
  } else {
    return null;
  }
}

String? _validateServerAddress(String input) {
  var value = input.trim().toLowerCase();
  var body = stripPrefix(value, 'quic://') ??
      stripPrefix(value, 'udp://') ??
      stripPrefix(value, 'tcp://') ??
      stripPrefix(value, 'wss://') ??
      stripPrefix(value, 'ws://') ??
      stripPrefix(value, 'dynamic://');
  body ??= value;

  if (body.startsWith('txt:')) {
    final txtDomainRegex = RegExp(r'^txt:[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    return txtDomainRegex.hasMatch(body) ? null : 'TXT 域名格式错误';
  }
  if (body.isEmpty) {
    return '服务器地址不能为空';
  }
  return null;
}

String _applyServerScheme(String input, String protocol) {
  var scheme = 'quic://';
  if (protocol == 'TCP') {
    scheme = 'tcp://';
  } else if (protocol == 'WSS') {
    scheme = 'wss://';
  } else if (protocol == 'DYNAMIC') {
    scheme = 'dynamic://';
  }
  var body = stripScheme(input.trim());
  if (body.isEmpty) {
    return '';
  }
  if (protocol == 'DYNAMIC' && body.toLowerCase().startsWith('txt:')) {
    body = body.substring(4);
  }
  return '$scheme$body';
}

String stripScheme(String input) {
  final pattern = RegExp(r'^[^:]+://');
  return input.replaceFirst(pattern, '');
}

String normalizeCommunicationMethod(String serverAddress) {
  final normalizedAddress = serverAddress.trim().toLowerCase();
  if (normalizedAddress.startsWith('quic://') ||
      normalizedAddress.startsWith('udp://')) {
    return 'QUIC';
  }
  if (normalizedAddress.startsWith('tcp://')) {
    return 'TCP';
  }
  if (normalizedAddress.startsWith('txt:')) {
    return 'DYNAMIC';
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
