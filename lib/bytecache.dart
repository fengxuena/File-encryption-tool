import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';



class ByteCache {
  final String cacheFileName;
  late String _filePath;

  ByteCache(this.cacheFileName) {}

  Future<void> initFilePath() async {
    final directory = await _getCacheDirectory();
    this._filePath = path.join(directory, cacheFileName.toString() + '.cache');
    _ensureDirectoryExists();
  }

  Future<String> _getCacheDirectory()async{
    if (Platform.isAndroid) {
      return (await getApplicationCacheDirectory()).path;
    } else if (Platform.isWindows) {
      var appDataPath = Platform.environment['LOCALAPPDATA'];
      return path.join(appDataPath!,'fengxue', 'detool', 'cache');
    } else {
      throw Exception('Unsupported platform');
    }
  }

  void _ensureDirectoryExists() {
    final directory = path.dirname(this._filePath);
    if (!Directory(directory).existsSync()) {
      Directory(directory).createSync(recursive: true);
    }
  }

  void createCacheFile() {
    if (!File(this._filePath).existsSync()) {
      File(this._filePath).createSync(recursive: true);
    }
  }

  void deleteCacheFile() {
    if (File(this._filePath).existsSync()) {
      File(this._filePath).deleteSync();
    }
  }

  void clearAllCacheFiles() {
    final directory = path.dirname(this._filePath);
    final cacheFiles = Directory(directory).listSync().where((entity) {
      return entity is File && entity.path.endsWith('.cache');
    });

    for (var file in cacheFiles) {
      file.deleteSync();
    }
  }

  Stream<List<int>> getInputStream() {
    Stream<List<int>> inputstream=File(this._filePath).openRead();
    return inputstream;
  }

  IOSink getOutputStream() {
    IOSink outputstream= File(this._filePath).openWrite();
    return outputstream;
  }
  String getname(){
    return this.cacheFileName;
  }
  String get_filePath() {
    return this._filePath;
  }
}

