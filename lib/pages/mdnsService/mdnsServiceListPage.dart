import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:oktoast/oktoast.dart';
import 'package:openiothub_grpc_api/proto/manager/mqttDeviceManager.pb.dart';
// import 'package:multicast_dns/multicast_dns.dart';
import 'package:openiothub/model/custom_theme.dart';
// import 'package:openiothub/pages/mdnsService/AddMqttDevicesPage.dart';
import 'package:openiothub/util/ThemeUtils.dart';
import 'package:openiothub_api/openiothub_api.dart';
import 'package:openiothub_common_pages/wifiConfig/smartConfigTool.dart';
import 'package:openiothub_constants/openiothub_constants.dart';
import 'package:openiothub_grpc_api/proto/mobile/mobile.pb.dart';
import 'package:openiothub_grpc_api/proto/mobile/mobile.pbgrpc.dart';
import 'package:openiothub_plugin/plugins/mdnsService/commWidgets/info.dart';
import 'package:openiothub_plugin/plugins/mdnsService/mdnsType2ModelMap.dart';
//统一导入全部设备类型
import 'package:openiothub_plugin/plugins/mdnsService/modelsMap.dart';
import 'package:provider/provider.dart';
import 'package:flutter_nsd/flutter_nsd.dart';

class MdnsServiceListPage extends StatefulWidget {
  MdnsServiceListPage({required Key key, required this.title})
      : super(key: key);

  final String title;

  @override
  _MdnsServiceListPageState createState() => _MdnsServiceListPageState();
}

class _MdnsServiceListPageState extends State<MdnsServiceListPage> {
  Utf8Decoder u8decodeer = Utf8Decoder();
  Map<String, PortService> _IoTDeviceMap = Map<String, PortService>();
  late Timer _timerPeriodLocal;
  late Timer _timerPeriodRemote;
  final flutterNsd = FlutterNsd();
  bool initialStart = true;
  bool _scanning = false;
  List<String> _supportedTypeList = MDNS2ModelsMap.getAllmDnsServiceType();

  @override
  void initState() {
    super.initState();
    flutterNsd.stream.listen(
          (NsdServiceInfo oneMdnsService) {
        setState(() {
          PortService _portService = PortService.create();
          _portService.ip = oneMdnsService.hostname!
              .replaceAll(RegExp(r'local.local.'), "local.");
          _portService.port = oneMdnsService.port!;
          _portService.isLocal = true;
          oneMdnsService.txt!.forEach((String key, Uint8List value) {
            _portService.info[key] = u8decodeer.convert(value);
          });
          print("print _portService:$_portService");
          addPortService(_portService);
        });
      },
      onError: (e) async {
        if (e is NsdError) {
          if (e.errorCode == NsdErrorCode.startDiscoveryFailed &&
              initialStart) {
          } else if (e.errorCode == NsdErrorCode.discoveryStopped &&
              initialStart) {
            initialStart = false;
          }
        }
      },
    );

    Future.delayed(Duration(milliseconds: 500)).then((value) {
      refreshmDNSServicesFromeLocal();
      refreshmDNSServicesFromeRemote();
    });
    _timerPeriodLocal = Timer.periodic(const Duration(seconds: 10), (Timer timer) {
      refreshmDNSServicesFromeLocal();
    });
    _timerPeriodRemote = Timer.periodic(const Duration(seconds: 5), (Timer timer) {
      refreshmDNSServicesFromeRemote();
    });
    print("init iot devie List");
  }

  @override
  Widget build(BuildContext context) {
    print("_IoTDeviceMap:$_IoTDeviceMap");
    final tiles = _IoTDeviceMap.values.map(
      (PortService pair) {
        var listItemContent = ListTile(
          leading: Icon(Icons.devices,
              color: Provider.of<CustomTheme>(context).isLightTheme()
                  ? CustomThemes.light.primaryColorLight
                  : CustomThemes.dark.primaryColorDark),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: <Widget>[
              Text(pair.info["name"]!, style: Constants.titleTextStyle),
            ],
          ),
          trailing: Constants.rightArrowIcon,
        );
        return InkWell(
          onTap: () {
            _pushDeviceServiceTypes(pair);
          },
          child: listItemContent,
        );
      },
    );
    final divided = ListTile.divideTiles(
      context: context,
      tiles: tiles,
    ).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        centerTitle: true,
        actions: <Widget>[
          IconButton(
              icon: Icon(
                Icons.refresh,
                color: Colors.white,
              ),
              onPressed: () {
                refreshmDNSServicesFromeLocal();
              }),
//            TODO 添加设备（类型：mqtt，小米，美的；设备型号：TC1-A1,TC1-A2）
//           IconButton(
//               icon: Icon(
//                 Icons.add_circle,
//                 color: Colors.white,
//               ),
//               onPressed: () {
// //                  TODO：手动添加MQTT设备
// //                   Scaffold.of(context).openDrawer();
//                 Navigator.of(context).push(
//                   MaterialPageRoute(
//                     builder: (context) {
//                       return AddMqttDevicesPage();
//                     },
//                   ),
//                 );
//               }),
        ],
      ),
      body: divided.length > 0
          ? ListView(children: divided)
          : Container(
              child: Column(children: [
                ThemeUtils.isDarkMode(context)
                    ? Image.asset('assets/images/empty_list_black.png')
                    : Image.asset('assets/images/empty_list.png'),
                TextButton(
                    style: ButtonStyle(
                      side: MaterialStateProperty.all(
                          BorderSide(color: Colors.grey, width: 1)),
                      shape: MaterialStateProperty.all(StadiumBorder()),
                    ),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) {
                            return SmartConfigTool(
                              title: "添加设备",
                              needCallBack: true,
                              key: UniqueKey(),
                            );
                          },
                        ),
                      );
                    },
                    child: Text("请先添加设备"))
              ]),
            ),
    );
  }

  @override
  void dispose() {
    super.dispose();
    _timerPeriodLocal.cancel();
    _timerPeriodRemote.cancel();
    _IoTDeviceMap.clear();
    stopDiscovery();
  }

//显示是设备的UI展示或者操作界面
  void _pushDeviceServiceTypes(PortService device) async {
    // 查看设备的UI，1.native，2.web
    // 写成独立的组件，支持刷新
    String? model = device.info["model"];

    if (ModelsMap.modelsMap.containsKey(model)) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) {
            return ModelsMap.modelsMap[model](device);
          },
        ),
      );
    } else {
//      TODO 没有可供显示的界面
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) {
            return InfoPage(
              portService: device,
              key: UniqueKey(),
            );
          },
        ),
      );
    }
//    await _IoTDeviceMap.clear();
    getIoTDeviceFromRemote();
  }

//获取所有的网络列表
  Future<List<SessionConfig>> getAllSession() async {
    try {
      final response = await SessionApi.getAllSession();
      print('getAllSession received: ${response.sessionConfigs}');
      return response.sessionConfigs;
    } catch (e) {
      List<SessionConfig> list = [];
      print('Caught error: $e');
      return list;
    }
  }

//获取所有的设备列表（本地网络和远程网络）

//刷新设备列表
  Future refreshmDNSServicesFromeLocal() async {
    getIoTDeviceFromLocal();
  }

  //刷新设备列表
  Future refreshmDNSServicesFromeRemote() async {
    if (await userSignedIn()) {
      getIoTDeviceFromMqttServer();
    }
    try {
      getAllSession().then((s) {
        s.forEach((SessionConfig sc) {
          SessionApi.refreshmDNSServices(sc);
        });
      }).then((_) async {
        getIoTDeviceFromRemote();
      });
    } catch (e) {
      print('Caught error: $e');
    }
  }

//添加设备
  Future<void> addPortService(PortService portService) async {
    if (!portService.info.containsKey("name") ||
        portService.info["name"] == null ||
        portService.info["name"] == "") {
      return;
    }
    print("addPortService:${portService.info}");
    String? id = portService.info["id"];
    String value = "";
    try {
      value = await CnameManager.GetCname(id!);
    } catch (e) {
      showToast( e.toString());
    }
    if (value != "" && value != null) {
      portService.info["name"] = value;
    }
    if (!_IoTDeviceMap.containsKey(id) ||
        (_IoTDeviceMap.containsKey(id) &&
            !_IoTDeviceMap[id]!.isLocal &&
            portService.isLocal)) {
      setState(() {
        _IoTDeviceMap[id!] = portService;
      });
    }
  }

  Future getIoTDeviceFromLocal() async {
    //优先iotdevice
    for (int i = 0; i < _supportedTypeList.length; i++) {
      await getIoTDeviceFromLocalByType(_supportedTypeList[i]);
      await Future.delayed(Duration(seconds: 1));
      await stopDiscovery();
    }
  }

  Future getIoTDeviceFromLocalByType(String serviceType) async {
    if (_scanning) return;
    _scanning = true;
    await flutterNsd.discoverServices(serviceType + ".");
  }

  Future<void> stopDiscovery() async {
    if (!_scanning) return;
    _scanning = false;
    await flutterNsd.stopDiscovery();
  }

  Future getIoTDeviceFromMqttServer() async {
    MqttDeviceInfoList mqttDeviceInfoList =
        await MqttDeviceManager.GetAllMqttDevice();
    mqttDeviceInfoList.mqttDeviceInfoList
        .forEach((MqttDeviceInfo mqttDeviceInfo) {
      PortService _portService = PortService();
      //  TODO
      _portService.ip = mqttDeviceInfo.mqttInfo.mqttServerHost;
      _portService.port = mqttDeviceInfo.mqttInfo.mqttServerPort;
      _portService.isLocal = false;
      _portService.info["name"] = mqttDeviceInfo.deviceDefaultName != ""
          ? mqttDeviceInfo.deviceDefaultName
          : mqttDeviceInfo.deviceModel;
      _portService.info["id"] = mqttDeviceInfo.deviceId;
      _portService.info["mac"] = mqttDeviceInfo.deviceId;
      _portService.info["model"] = mqttDeviceInfo.deviceModel;
      _portService.info["username"] =
          mqttDeviceInfo.mqttInfo.mqttClientUserName;
      _portService.info["password"] =
          mqttDeviceInfo.mqttInfo.mqttClientUserPassword;
      _portService.info["client-id"] = mqttDeviceInfo.mqttInfo.mqttClientId;
      _portService.info["tls"] = mqttDeviceInfo.mqttInfo.sSLorTLS.toString();
      _portService.info["enable_delete"] = true.toString();
      addPortService(_portService);
    });
  }

  Future getIoTDeviceFromRemote() async {
    // TODO 从搜索到的mqtt组件中获取设备
    try {
      // 从远程获取设备
      getAllSession().then((List<SessionConfig> sessionConfigList) {
        sessionConfigList.forEach((SessionConfig sessionConfig) {
          SessionApi.getAllTCP(sessionConfig).then((t) {
            t.portConfigs.forEach((portConfig) {
              PortService? _portService;
              if (MDNS2ModelsMap.modelsMap
                  .containsKey(portConfig.mDNSInfo.info["service"])) {
                _portService = MDNS2ModelsMap
                    .modelsMap[portConfig.mDNSInfo.info["service"]]!
                    .clone();
                _portService.info.addAll(portConfig.mDNSInfo.info);
                _portService.ip = "127.0.0.1";
                _portService.port = portConfig.localProt;
                _portService.isLocal = false;
                if (_portService.info.containsKey("id") &&
                    _portService.info["id"] == "" &&
                    _portService.info.containsKey("mac") &&
                    _portService.info["mac"] != "") {
                  _portService.info["id"] = _portService.info["mac"]!;
                } else {
                  _portService.info["id"] =
                      "${portConfig.device.addr}:${_portService.port}@local";
                }
                addPortService(_portService);
              } else {
                addPortService(portConfig.mDNSInfo);
              }
            });
          });
        });
      });
    } catch (e) {
      showDialog(
          context: context,
          builder: (_) => AlertDialog(
                  title: Text("从远程获取物联网列表失败："),
                  content: Text("失败原因：$e"),
                  actions: <Widget>[
                    TextButton(
                      child: Text("确认"),
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                    )
                  ]));
    }
  }
}

//              print("mDNSInfo:$mDNSInfo");
//              {
//                "name": "esp-switch-80:7D:3A:72:64:6F",
//                "type": "_iotdevice._tcp",
//                "domain": "local",
//                "hostname": "esp-switch-80:7D:3A:72:64:6F.local.",
//                "port": 80,
//                "text": null,
//                "ttl": 4500,
//                "AddrIPv4": ["192.168.0.3"],
//                "AddrIPv6": null
//              }
