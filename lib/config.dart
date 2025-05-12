import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

enum EncryptionMethod {
  ADD_RANDOM,
  AES,
  FENCE,
  BASE64,
  SPLIT_PART,
}
extension EncryptionMethodExtension on EncryptionMethod {
  String get name {
    return toString().split('.').last;
  }
}
class Config {
  late String _filePath;
  Map<String, dynamic> _defaultSettings = {
    'encryption_methods': [
      EncryptionMethod.ADD_RANDOM.name,
      EncryptionMethod.AES.name,
      EncryptionMethod.FENCE.name,
      EncryptionMethod.BASE64.name,
    ],
    'upload_to_webdav': false,
    'webdav_url': '',
    'webdav_username': '',
    'webdav_password': '',
  };

  Config() {}

  Future<void> initFilePath() async {
    _filePath = await _getFilePath();
    if (!File(_filePath).existsSync()) {
      Directory(path.dirname(_filePath)).createSync(recursive: true);
      File(_filePath).writeAsStringSync(jsonEncode(_defaultSettings));
    }
  }

  Future<String> _getFilePath() async {
    if (Platform.isAndroid) {
      return path.join((await getApplicationDocumentsDirectory()).path, "setting.json");
    } else if (Platform.isWindows) {
      final appDataPath = Platform.environment['LOCALAPPDATA'];
      return path.join(appDataPath!, 'fengxue', 'detool', 'setting.json');
    } else {
      throw Exception('Unsupported platform');
    }
  }

  Map<String, dynamic> get_setting() {
    if (!File(_filePath).existsSync()) {
      throw Exception('Configuration file does not exist');
    }
    final content = File(_filePath).readAsStringSync();
    return jsonDecode(content);
  }

  void set_setting(Map<String, dynamic> settings) {
    File(_filePath).writeAsStringSync(jsonEncode(settings));
  }
  //获取当前配置的加密方法
  List<EncryptionMethod> getEncryptionMethods() {
    final settings = get_setting();
    return List<EncryptionMethod>.from(
      settings['encryption_methods'].map((method) => EncryptionMethod.values.firstWhere((e) => e.name == method)),
    );
  }

}