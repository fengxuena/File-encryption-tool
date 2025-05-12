import 'dart:convert';
import 'dart:typed_data';
import 'package:detool/bytecache.dart';
import 'package:encrypt/encrypt.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'config.dart'; 
import 'deencrypt.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:permission_handler/permission_handler.dart';
import 'package:fluttertoast/fluttertoast.dart';

Future<void> main() async {
  runApp(const MyApp());
  var config=Config();
  await config.initFilePath();
  var bytecache=ByteCache("main");
  await bytecache.initFilePath();
  bytecache.clearAllCacheFiles();
  checkAndRequestPermissions();
}
Future<void> checkAndRequestPermissions() async {
  if (Platform.isAndroid) {
    var status = await Permission.manageExternalStorage.status;
    if (!status.isGranted) {
      await Permission.manageExternalStorage.request();
      if (!await Permission.manageExternalStorage.isGranted) {
        // 显示 Toast 提示
          Fluttertoast.showToast(
          msg: "请授予所有文件管理权限以使用",
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.BOTTOM,
          timeInSecForIosWeb: 1,
          backgroundColor: Colors.red,
          textColor: Colors.white,
          fontSize: 16.0,
        );
        openAppSettings();
      }
    }
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final TextEditingController _outputPathController = TextEditingController();//输出路径
  List<String> _filePaths = []; // 存储文件路径的列表
  Config config = Config(); // 初始化Config类

  //按钮功能
  void _addFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      allowMultiple: true, // 允许多选
    );

    if (result != null) {
      setState(() {
        _filePaths.addAll(result.paths.whereType<String>()); // 将选择的文件路径添加到列表中
      });}
  }
  void _cleanFile() {
    setState(() {_filePaths.clear(); });
  }
  void _encryFile() async {
    if (_outputPathController.text.isEmpty) {
      await _showAlert('请设置输出路径');
      return;}
    if (_filePaths.isEmpty) {
      await _showAlert('请添加文件');
      return;}
    String? password= await _showPasswordDialog();
    if (password==null) {return;}
    await config.initFilePath();
    var encryptionMethods = config.getEncryptionMethods();
    ProgressDialog progressDialog = new ProgressDialog(title: '加密文件',message: '正在加密文件...',);
    progressDialog.show(context);
    var myencry = myEncry(
                    _filePaths, 
                    sortByEncryptionOrder(encryptionMethods), 
                    _outputPathController.text, 
                    _hashPassword(password),
                    progressDialog,
                    onDecryptionComplete: _onDecryptionComplete);
    myencry.encryptFiles();
    progressDialog.bindstop(myencry);
  }
  void _decryFile() async {
    if (_outputPathController.text.isEmpty) {
      await _showAlert('请设置输出路径');
      return;}
    if (_filePaths.isEmpty) {
      await _showAlert('请添加文件');
      return;}
    String? password= await _showPasswordDialog();
    if (password==null) {return;}  
    await config.initFilePath();
    var encryptionMethods = config.getEncryptionMethods();
    ProgressDialog progressDialog = ProgressDialog(
      title: '解密文件',
      message: '正在解密文件...',
    );
    progressDialog.show(context);
    var mydecry = myDecry(
                      _filePaths, 
                      _outputPathController.text, 
                      _hashPassword(password),
                      progressDialog,
                      onDecryptionComplete: _onDecryptionComplete);
    mydecry.decryptFiles();
    progressDialog.bindstop(mydecry);
  }
  void _setSetting() async{
    await config.initFilePath();
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('设置'),
          content: SettingForm(config: config),
        );
      },
    );
  }
  void _about(){
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text('关于'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text("""版本：DeTool v1.0.0\n作者：@Fengxue\n
使用方式：\n
1.打开设置选择加密方式并保存。\n
2.添加要加密/解密的文件，并设置输出路径。\n
3.输入密码，点击确定。\n
4.等待加密/解密完成。\n
5.解密完成后，将解密后的文件保存到指定路径。\n
6.加密后的文件后缀为.en。\n
7.关于webdav还未实现，后续有空再完善，需求不高。\n\n
注意事项：\n
当使用分割1/10作为密钥时请妥善保管密钥文件(.sp)\n
解密时需要将1/10的密钥的文件(.sp)放到同目录下\n
且密钥文件名称与解密文件一致"""),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            child: Text('关闭'),
            onPressed: () {
              Navigator.of(context).pop();
            },
          )
        ]
      );
    }
  );
}
  void _setOutPath() async {
    String? result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {setState(() {_outputPathController.text = result;});}
  }
  
  // 根据枚举的原始声明顺序排序（使用 index 属性）
  List<EncryptionMethod> sortByEncryptionOrder(List<EncryptionMethod> list) {
  list.sort((a, b) => a.index.compareTo(b.index));
  return list;
  }
  // 显示弹窗提示
  Future<void> _showAlert(String message) async{
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('提示'),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              child: Text('确定'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }
  // 显示密码输入对话框
  Future<String?> _showPasswordDialog() async {
    final TextEditingController passwordController = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('输入密码'),
          content: TextField(
            controller: passwordController,
            decoration: InputDecoration(labelText: '密码'),
            obscureText: true,
          ),
          actions: <Widget>[
            TextButton(
              child: Text('取消'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text('确定'),
              onPressed: () {
                Navigator.of(context).pop(passwordController.text);
              },
            ),
          ],
        );
      },
    );
}
  //密码哈希
  String _hashPassword(String password) {
    final hash = crypto.sha256.convert(utf8.encode(password)).bytes;
    return base64.encode(hash); // 将哈希值编码为Base64字符串
}
   // 解密完成后的操作
  void _onDecryptionComplete(String msg) async{
    setState(() {
      _filePaths.clear(); // 清空文件路径列表
    });
    await _showAlert(msg); // 显示解密完成的对话框
  }
  // 自定义按钮样式
  final ButtonStyle elevatedButtonStyle = ElevatedButton.styleFrom(
    minimumSize: Size(150, 40), // 设置按钮的最小宽度和高度
    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8), // 设置按钮的内边距
  );
  // 界面构建
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: null, // 去掉标题栏
      body: Row(
        children: [
          Expanded(
            flex: 4,
            child: Container(
              color: Colors.grey[200], // 设置背景颜色
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, // 使子部件左对齐
                  children: [
                    // 文件列表:
                    Text('文件列表：', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    SizedBox(height: 8), // 添加间距
                    // 列表框
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.black), // 添加黑色边框
                        ),
                        child: ListView.builder(
                          itemCount: _filePaths.length, // 使用文件路径列表的长度
                          itemBuilder: (context, index) {
                            return ListTile(
                              title: Text(_filePaths[index]), // 显示文件路径
                            );
                          },
                        ),
                      ),
                    ),
                    SizedBox(height: 8), // 添加间距
                    // 文件输出路径
                    TextField(
                      controller: _outputPathController,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: '输出路径：',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Container(
              color: Colors.grey[200], // 设置背景颜色
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: _addFile,
                    style:elevatedButtonStyle,
                    child: const Text('添加文件'),
                  ),
                  ElevatedButton(
                    onPressed: _cleanFile,
                    style:elevatedButtonStyle,
                    child: const Text('清空列表'),
                  ),
                  ElevatedButton(
                    onPressed: _encryFile,
                    style:elevatedButtonStyle,
                    child: const Text('加密文件'),
                  ),
                  ElevatedButton(
                    onPressed: _decryFile,
                    style:elevatedButtonStyle,
                    child: const Text('解密文件'),
                  ),
                  ElevatedButton(
                    onPressed: _setSetting,
                    style:elevatedButtonStyle,
                    child: const Text('设置'),
                  ),
                  ElevatedButton(
                    onPressed: _about,
                    style:elevatedButtonStyle,
                    child: const Text('关于'),
                  ),
                  ElevatedButton(
                    onPressed: _setOutPath,
                    style:elevatedButtonStyle,
                    child: const Text('设置输出路径'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SettingForm extends StatefulWidget {
  final Config config;

  SettingForm({required this.config});

  @override
  _SettingFormState createState() => _SettingFormState();
}

class _SettingFormState extends State<SettingForm> {
  late Map<String, dynamic> _settings;
  final TextEditingController _webdavUrlController = TextEditingController();
  final TextEditingController _webdavUsernameController = TextEditingController();
  final TextEditingController _webdavPasswordController = TextEditingController();
  List<EncryptionMethod> _encryptionMethods = [];

  @override
  void initState() {
    super.initState();
    _settings = widget.config.get_setting();
    _encryptionMethods = List<EncryptionMethod>.from(
      _settings['encryption_methods'].map((method) => EncryptionMethod.values.firstWhere((e) => e.name == method)),
    );
    _webdavUrlController.text = _settings['webdav_url'];
    _webdavUsernameController.text = _settings['webdav_username'];
    _webdavPasswordController.text = _settings['webdav_password'];
  }

  void _saveSettings() {
    _settings['encryption_methods'] = _encryptionMethods.map((e) => e.name).toList();
    _settings['webdav_url'] = _webdavUrlController.text;
    _settings['webdav_username'] = _webdavUsernameController.text;
    _settings['webdav_password'] = _webdavPasswordController.text;
    widget.config.set_setting(_settings);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          CheckboxListTile(
            title: Text('添加随机数'),
            value: _encryptionMethods.contains(EncryptionMethod.ADD_RANDOM),
            onChanged: (bool? value) {
              setState(() {
                if (value!) {
                  _encryptionMethods.add(EncryptionMethod.ADD_RANDOM);
                } else {
                  _encryptionMethods.remove(EncryptionMethod.ADD_RANDOM);
                }
              });
            },
          ),
          CheckboxListTile(
            title: Text('AES'),
            value: _encryptionMethods.contains(EncryptionMethod.AES),
            onChanged: (bool? value) {
              setState(() {
                if (value!) {
                  _encryptionMethods.add(EncryptionMethod.AES);
                } else {
                  _encryptionMethods.remove(EncryptionMethod.AES);
                }
              });
            },
          ),
          CheckboxListTile(
            title: Text('栏栅加密'),
            value: _encryptionMethods.contains(EncryptionMethod.FENCE),
            onChanged: (bool? value) {
              setState(() {
                if (value!) {
                  _encryptionMethods.add(EncryptionMethod.FENCE);
                } else {
                  _encryptionMethods.remove(EncryptionMethod.FENCE);
                }
              });
            },
          ),
          CheckboxListTile(
            title: Text('BASE64'),
            value: _encryptionMethods.contains(EncryptionMethod.BASE64),
            onChanged: (bool? value) {
              setState(() {
                if (value!) {
                  _encryptionMethods.add(EncryptionMethod.BASE64);
                } else {
                  _encryptionMethods.remove(EncryptionMethod.BASE64);
                }
              });
            },
          ),
          CheckboxListTile(
            title: Text('分割1/10作为密钥'),
            value: _encryptionMethods.contains(EncryptionMethod.SPLIT_PART),
            onChanged: (bool? value) {
              setState(() {
                if (value!) {
                  _encryptionMethods.add(EncryptionMethod.SPLIT_PART);
                } else {
                  _encryptionMethods.remove(EncryptionMethod.SPLIT_PART);
                }
              });
            },
          ),
          CheckboxListTile(
            title: Text('是否上传WebDAV'),
            value: _settings['upload_to_webdav'],
            onChanged: (bool? value) {
              setState(() {
                _settings['upload_to_webdav'] = value!;
              });
            },
          ),
          TextField(
            controller: _webdavUrlController,
            decoration: InputDecoration(labelText: 'WebDAV地址'),
          ),
          TextField(
            controller: _webdavUsernameController,
            decoration: InputDecoration(labelText: 'WebDAV账号'),
          ),
          TextField(
            controller: _webdavPasswordController,
            decoration: InputDecoration(labelText: 'WebDAV密码'),
            obscureText: true,
          ),
          SizedBox(height: 20),
          ElevatedButton(
            onPressed: _saveSettings,
            child: Text('保存'),
          ),
        ],
      ),
    );
  }
}

class ProgressDialog {
  static ProgressDialog? _instance;
  static BuildContext? _dialogContext;
  final String title;
  final String message;
  StopMethod? _stopMethod;
  int _max = 0; // 进度条的最大值
  int _progress = 0; // 当前进度

  ProgressDialog({required this.title, required this.message});

  void setmax(int max) {
    _max = max;
  }

  void updata(int progress) {
    _progress = progress;
    updateProgress();
  }

  void show(BuildContext context) {
    if (_instance != null) {
      return; // 如果已经有一个实例，则不显示新的对话框
    }
    _instance = this;
    showDialog(
      context: context,
      barrierDismissible: false, // 用户不能通过点击对话框外部来关闭它
      builder: (BuildContext context) {
        _dialogContext = context;
        return AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message),
              SizedBox(height: 20),
              LinearProgressIndicator(
                value: _max == 0 ? 0 : _progress / _max,
              ),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  if (_stopMethod != null) {
                    _stopMethod!.stop(true);
                  }
                  closeDialog();
                },
                child: Text('中断'),
              ),
            ],
          ),
        );
      },
    );
  }

  void updateProgress() {
      if (_progress >= _max) {
        closeDialog();
      }
  }

  void bindstop(StopMethod stopMethod){
    _stopMethod=stopMethod;
  }

  void closeDialog() {
    if (_dialogContext != null) {
      Navigator.of(_dialogContext!).pop();
      _dialogContext = null;
      _instance = null;
    }
  }
}