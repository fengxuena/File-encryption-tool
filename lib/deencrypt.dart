import 'package:detool/bytecache.dart';
import 'package:detool/config.dart';
import 'package:detool/main.dart';
import 'dart:math';
import 'dart:ui';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:crypto/crypto.dart' as crypto;

//先获取两个列表，一个文件路径列表，一个加密方法列表
//然后遍历，逐个加密，加密前加密时全部使用缓存文件来传递，最后输出缓存类将缓存文件转化为文件
abstract class StopMethod {
  void stop(bool isStop);
}

//加密
class myEncry implements StopMethod {
  List<String> _filePaths;
  List<EncryptionMethod> _encryptionMethods;
  String _outputpath;
  String _secret;
  final void Function(String)? onDecryptionComplete; // 回调函数
  ProgressDialog _progressDialog;// 进度条
  bool _isStopRequested = false; // 中断标志
  ByteCache _cacheFile=new ByteCache("encry");
  //构造器
  myEncry(this._filePaths,
          this._encryptionMethods,
          this._outputpath,
          this._secret, 
          this._progressDialog,
          {this.onDecryptionComplete}) {}
  @override//终止加密，关闭流，并删除所有缓存文件
  void stop(bool isStop) {
    _isStopRequested = isStop;
    _progressDialog.closeDialog();
    this.close();
  }
  //遍历加密
  void encryptFiles() async {
    _progressDialog.setmax(_filePaths.length);
    int currentProgress = 0;
    await _cacheFile.initFilePath();
    _cacheFile.createCacheFile();
    await Future.forEach(_filePaths, (filePath) async {
      await encryptFile(filePath); // 确保每次加密操作完成后再继续下一个
      currentProgress++;// 更新进度条的当前进度
      _progressDialog.updata(currentProgress);
      if(_isStopRequested){
        this.close();
        _progressDialog.closeDialog();
        return;}
      _cacheFile.clearAllCacheFiles();
    });

    onDecryptionComplete?.call("加密完成！加密文件为(filename.extension.en)，分割的文件为(filename.extension.sp)");
  }
  // 加密文件处理
  Future<void> encryptFile(String filePath) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      errormsg('File does not exist: $filePath');}
    // 创建初始缓存文件
    var cachefile = ByteCache("initial");
    await cachefile.initFilePath();
    cachefile.createCacheFile();
    var cacheoutput = cachefile.getOutputStream();
    try {
      final inputStream = file.openRead();
      await inputStream.pipe(cacheoutput);
    } catch (e) {errormsg('Error copying file: $e');
    } finally {await cacheoutput.close();}
    // 依次调用加密方法
    ByteCache resultCacheFile = cachefile;
    
    for (var method in _encryptionMethods) {
      
      resultCacheFile = await encryptContent(resultCacheFile, method,filePath);
      
      if (_isStopRequested){
        this.close();
        return;}
    }
    // 提取文件名和后缀
    final fileName = path.basename(filePath);
    final baseFileName = path.basenameWithoutExtension(fileName);
    final extension = path.extension(fileName);
  
    String originalName = '$baseFileName$extension';
    String suffix = '.en';
    String newName = '$originalName$suffix';
    String newFilePath = path.join(_outputpath, newName);

    // 检查文件是否存在，存在则删除
    if (File(newFilePath).existsSync()) {
      File(newFilePath).deleteSync();
    }

    // 确保输出目录存在
    _ensureDirectoryExists(_outputpath);
    // 创建新文件并写入最终加密结果
    final outputFile = File(newFilePath);
    await outputFile.create();
    final outputStream2 = outputFile.openWrite();
    try {
      // 将加密方法的二进制数写入文件头部
      int binary = _encryptionMethodsToBinary(_encryptionMethods);
      outputStream2.add([binary]);
      var inputStream2 = resultCacheFile.getInputStream();
      await inputStream2.pipe(outputStream2);
    } catch (e) {errormsg('Error writing to output file: $e');
    } finally {outputStream2.close();}
  }
  //使用对应的加密方法
  Future<ByteCache> encryptContent(ByteCache cachefile, EncryptionMethod method,String filepath) async {
    if(_isStopRequested){
      return _cacheFile;
    }else{
      switch (method) {
            case EncryptionMethod.ADD_RANDOM:
              return (await random_encry(cachefile));
            case EncryptionMethod.AES:
              return (await aes_encry(cachefile));
            case EncryptionMethod.FENCE:
              return (await fence_encry(cachefile));
            case EncryptionMethod.BASE64:
              return (await base64_encry(cachefile));
            case EncryptionMethod.SPLIT_PART:
              return (await split_encry(cachefile,filepath));
      }}
  }
  //添加随机数
  Future<ByteCache> random_encry(ByteCache cachefile) async {
    // 创建一个新的缓存文件
    ByteCache newCacheFile = ByteCache("random_encry");   
    await newCacheFile.initFilePath();
    newCacheFile.createCacheFile();
    IOSink newCacheOutputStream = newCacheFile.getOutputStream();
    // 获取原缓存文件的路径
    String originalFilePath = cachefile.get_filePath();
    File originalFile = File(originalFilePath);
    // 获取原缓存文件的大小
    int fileSize = originalFile.lengthSync();
    
    if (!originalFile.existsSync()) {throw Exception('缓存文件不存在: $originalFilePath');}
    
    
    // 使用滑动窗口读取原缓存文件的 1024 字节
    RandomAccessFile randomAccessFile = originalFile.openSync(mode: FileMode.read);
    try {
      int bytesRead = 0;
      Random random = Random();
      while (bytesRead < fileSize) {
        int bytesToRead = min(512, fileSize - bytesRead);
        Uint8List buffer = randomAccessFile.readSync(bytesToRead);
        // 每隔 1 位字节添加 1 位随机数，譬如：01r23r45r67r9
        List<int> newBuffer = [];
        for (int i = 0; i < buffer.length; i++) {
          newBuffer.add(buffer[i]); // 当前字节数据
          newBuffer.add(random.nextInt(254));}
        // 将处理后的内容写入新的缓存文件
        newCacheOutputStream.add(newBuffer);
        bytesRead += bytesToRead;
        
      }
      } catch (e) {
          // 关闭文件流
          await randomAccessFile.close();
          await newCacheOutputStream.close();
        errormsg("添加随机数错误："+e.toString());}
        finally{
          // 关闭文件流
          await randomAccessFile.close();
          await newCacheOutputStream.close();}
      return newCacheFile;
}
  //AES加密
  Future<ByteCache> aes_encry(ByteCache cachefile) async {
  ByteCache newCacheFile = ByteCache("aes_encry");
  await newCacheFile.initFilePath();
  newCacheFile.createCacheFile();
  IOSink newCacheOutputStream = newCacheFile.getOutputStream();
  String originalFilePath = cachefile.get_filePath();
  File originalFile = File(originalFilePath);
  int fileSize = originalFile.lengthSync();
  
  if (!originalFile.existsSync()) {throw Exception('缓存文件不存在: $originalFilePath');}
  // 生成密钥和初始 IV
  Uint8List key = _generateKeyFromSecret(_secret);
  Uint8List iv = _generateIVFromSecret(); // 初始 IV
  
  
  final encrypter = encrypt.Encrypter(encrypt.AES(encrypt.Key(key), mode: encrypt.AESMode.cbc,padding: null));
  // 将初始 IV 写入文件头部
  newCacheOutputStream.add(iv);
  RandomAccessFile randomAccessFile = originalFile.openSync(mode: FileMode.read);
  try {
    int bytesRead = 0;
    // 保存前一个加密块的最后 16 字节（用于链式 IV）
    Uint8List previousBlock = iv;
    while (bytesRead < fileSize) {
      int bytesToRead = min(1024, fileSize - bytesRead);
      Uint8List buffer = randomAccessFile.readSync(bytesToRead);
      // 临时存储未填充数据，最后统一填充
      Uint8List unpaddedBuffer = buffer;
      // 如果是最后一个分块，进行填充
      // 关键修复：如果是最后一个分块，无论大小如何都填充
      if (bytesRead + bytesToRead >= fileSize) {
        unpaddedBuffer = _padBuffer(buffer, 16);
      } else {
        unpaddedBuffer = buffer;
      }
      // 加密当前分块，使用前一个块的末尾 16 字节作为 IV
      final encrypted = encrypter.encryptBytes(
        unpaddedBuffer,
        iv: encrypt.IV(previousBlock),);
      // 写入加密数据
      newCacheOutputStream.add(encrypted.bytes);
      // 更新前一个块的末尾 16 字节
      previousBlock = encrypted.bytes.sublist(
        encrypted.bytes.length - 16,
        encrypted.bytes.length,
      );
      bytesRead += bytesToRead;
    }
    
  } catch (e) {
    await randomAccessFile.close();
    await newCacheOutputStream.close();
   errormsg("AES加密错误："+e.toString());
  } finally {
    await randomAccessFile.close();
    await newCacheOutputStream.close();
  }
  return newCacheFile;
}
  //栏栅加密
  Future<ByteCache> fence_encry(ByteCache cachefile)async{
    // 创建一个新的缓存文件
    ByteCache newCacheFile = ByteCache("fence_encry");
    await newCacheFile.initFilePath();
    newCacheFile.createCacheFile();
    IOSink newCacheOutputStream = newCacheFile.getOutputStream();
    // 获取原缓存文件的路径
    String originalFilePath = cachefile.get_filePath();
    File originalFile = File(originalFilePath);
    // 获取原缓存文件的大小
    int fileSize = originalFile.lengthSync();
    if (!originalFile.existsSync()) {throw Exception('缓存文件不存在: $originalFilePath');}
    
    // 使用滑动窗口读取原缓存文件的 1024 字节
    RandomAccessFile randomAccessFile = originalFile.openSync(mode: FileMode.read);
    try {
    int bytesRead = 0;
    Random random = Random();
    while (bytesRead < fileSize) {
      int bytesToRead = min(1024, fileSize - bytesRead);
      Uint8List buffer = randomAccessFile.readSync(bytesToRead);
      // 将处理后的内容写入新的缓存文件
      newCacheOutputStream.add(fences(buffer));
      bytesRead += bytesToRead;}
    
  } catch (e) {
    await randomAccessFile.close();
    await newCacheOutputStream.close();
    errormsg("栏栅加密错误："+e.toString());
  } finally{
    // 关闭文件流
    await randomAccessFile.close();
    await newCacheOutputStream.close();}
    return newCacheFile;
  }
  //base64加密
  Future<ByteCache> base64_encry(ByteCache cachefile) async {
  // 创建一个新的缓存文件
    ByteCache newCacheFile = ByteCache("base64_encry");
    await newCacheFile.initFilePath();
    newCacheFile.createCacheFile();
    IOSink newCacheOutputStream = newCacheFile.getOutputStream();  
    // 获取原缓存文件的路径
    String originalFilePath = cachefile.get_filePath();
    File originalFile = File(originalFilePath);

    // 获取原缓存文件的大小
    int fileSize = originalFile.lengthSync();
    
    if (!originalFile.existsSync()) {
      throw Exception('缓存文件不存在: $originalFilePath');
    }
    // 使用滑动窗口读取原缓存文件的 1020 字节
    RandomAccessFile randomAccessFile = originalFile.openSync(mode: FileMode.read);
    try {   
    int bytesRead = 0;
    while (bytesRead < fileSize) {
      List<int> buffer = [];
      int bytesToRead = min(1020, fileSize - bytesRead);
      buffer.addAll(randomAccessFile.readSync(bytesToRead));
      // 进行 Base64 编码
      String base64EncodedString = base64Encode(buffer);
      // 将编码后的内容写入新的缓存文件
      newCacheOutputStream.add(utf8.encode(base64EncodedString));
      bytesRead += bytesToRead;
    }
    
  } catch (e) {
     await randomAccessFile.close();
     await newCacheOutputStream.close();
     errormsg("Base64加密错误："+e.toString());
  } finally{
    // 关闭文件流
    await randomAccessFile.close();
    await newCacheOutputStream.close();}
    return newCacheFile;
}
  //分割加密
  Future<ByteCache> split_encry(ByteCache cachefile, String filepath) async {
  // 创建一个新的缓存文件
    ByteCache newCacheFile = ByteCache("split_encry");
    await newCacheFile.initFilePath();
    newCacheFile.createCacheFile();
    IOSink newCacheOutputStream = newCacheFile.getOutputStream();  
    
    // 获取原缓存文件的路径
    String originalFilePath = cachefile.get_filePath();
    File originalFile = File(originalFilePath);
    // 获取原缓存文件的大小
    int fileSize = originalFile.lengthSync();
    if (!originalFile.existsSync()) {
      throw Exception('缓存文件不存在: $originalFilePath');
    }
    
    // 计算前1/10数据的大小
    int splitSize = fileSize ~/ 10;

    // 提取文件名和后缀
    final fileName = path.basename(filepath);
    final baseFileName = path.basenameWithoutExtension(fileName);
    final extension = path.extension(fileName);
    String originalName = '$baseFileName$extension';
    String suffix = '.sp';
    String newName = '$originalName$suffix';
    String splitFilePath = path.join(_outputpath, newName);
    // 循环检查文件是否存在，存在则追加后缀
    while (File(splitFilePath).existsSync()) {
      File(splitFilePath).deleteSync();
    }

    // 创建并写入前1/10的数据到新的文件
    File splitFile = File(splitFilePath);
    await splitFile.create();
    IOSink splitOutputStream = splitFile.openWrite();

    // 使用滑动窗口读取原缓存文件的前1/10字节
    RandomAccessFile randomAccessFile = originalFile.openSync(mode: FileMode.read);
    try {
    int bytesRead = 0;
    while (bytesRead < splitSize) {
      int bytesToRead = min(1024, splitSize - bytesRead);
      Uint8List buffer = randomAccessFile.readSync(bytesToRead);
      splitOutputStream.add(buffer);
      bytesRead += bytesToRead;
    }} catch (e) {
      // 关闭文件流
      await randomAccessFile.close();
      await splitOutputStream.close();
      errormsg("分割加密错误："+e.toString());
    }finally{
      // 关闭文件流
      await randomAccessFile.close();
      await splitOutputStream.close();}
    // 读取剩下的9/10的数据
    RandomAccessFile randomAccessFile2 = originalFile.openSync(mode: FileMode.read);
    try{
    randomAccessFile2.setPositionSync(splitSize);
    int bytesRead2 = 0;
    while (bytesRead2 < fileSize - splitSize) {
      int bytesToRead = min(1024, fileSize - splitSize - bytesRead2);
      Uint8List buffer = randomAccessFile2.readSync(bytesToRead);
      newCacheOutputStream.add(buffer);
      bytesRead2 += bytesToRead;
    }
    
  } catch (e) {
    await randomAccessFile2.close();
    await newCacheOutputStream.close();

  } finally{
    // 关闭文件流
    await randomAccessFile2.close();
    await newCacheOutputStream.close();}
  return newCacheFile;
}
  // 生成密钥
  Uint8List _generateKeyFromSecret(String secret) {
    String repeatedSecret = secret * ((32 / secret.length).ceil());// 如果密码长度不足 32 字节，则重复复制密码
    // 截取前 32 字节作为密钥
    return Uint8List.fromList(utf8.encode(repeatedSecret).sublist(0, 32));
}
  // 生成IV
  Uint8List _generateIVFromSecret() {
  // 生成一个随机的16字节IV
  Random random = Random.secure();
  Uint8List iv = Uint8List(16);
  for (int i = 0; i < 16; i++) {
    iv[i] = random.nextInt(256);
  }
  return iv;
}
  // 填充数据以满足AES块大小要求
  Uint8List _padBuffer(Uint8List buffer, int blockSize) {
    int paddingLength = blockSize - (buffer.length % blockSize);
    if (paddingLength == 0) {
      paddingLength = blockSize;
    }
    List<int> padding = List<int>.filled(paddingLength, paddingLength);
    
    
    return Uint8List.fromList([...buffer, ...padding]);
  }
  //栅栏加密具体实现
  Uint8List fences(Uint8List buffer) {
  int length = buffer.length;
  Uint8List outqian = Uint8List(length);
  Uint8List outhou = Uint8List(length);
  Uint8List outlast = Uint8List(length * 2);

  for (int i = 0; i < length; i++) {
    int binaryDatum = buffer[i];
    int wei8 = binaryDatum >> 0 & 1;
    int wei7 = binaryDatum >> 1 & 1;
    int wei6 = binaryDatum >> 2 & 1;
    int wei5 = binaryDatum >> 3 & 1;
    int wei4 = binaryDatum >> 4 & 1;
    int wei3 = binaryDatum >> 5 & 1;
    int wei2 = binaryDatum >> 6 & 1;
    int wei1 = binaryDatum >> 7 & 1;
    int cc = wei1 * 8 + wei3 * 4 + wei5 * 2 + wei7 * 1;
    int cc2 = wei2 * 8 + wei4 * 4 + wei6 * 2 + wei8 * 1;
    outqian[i] = cc;
    outhou[i] = cc2;
  }
  
  

  for (int i = 0; i < length; i++) {
    outlast[i] = outqian[i];
    outlast[i + length] = outhou[i];
  }
  

  Uint8List output = Uint8List(length);
  int aa=0;
  for (int index = 0; index < outlast.length; index+=2) {
    int yu4 = outlast[index] % 2;
    int yu3 = (outlast[index] ~/ 2) % 2;
    int yu2 = (outlast[index] ~/ 4) % 2;
    int yu1 = (outlast[index] ~/ 8) % 2;
    int yu8 = outlast[index + 1] % 2;//不能用length
    int yu7 = (outlast[index + 1] ~/ 2) % 2;
    int yu6 = (outlast[index + 1] ~/ 4) % 2;
    int yu5 = (outlast[index + 1] ~/ 8) % 2;
    int newnub = yu1 * 128 + yu2 * 64 + yu3 * 32 + yu4 * 16 + yu5 * 8 + yu6 * 4 + yu7 * 2 + yu8 * 1;
    
    output[aa] = newnub;
    aa+=1;
  }

  return output;
}
  //确保输出目录存在
  void _ensureDirectoryExists(String directory) {
    if (!Directory(directory).existsSync()) {
      Directory(directory).createSync(recursive: true);
    }
}
  //写入头文件
  int _encryptionMethodsToBinary(List<EncryptionMethod> methods) {
  int binary = 0;
  for (var method in methods) {
    switch (method) {
      case EncryptionMethod.ADD_RANDOM:
        binary |= 1 << 0; // 第1位
        break;
      case EncryptionMethod.AES:
        binary |= 1 << 1; // 第2位
        break;
      case EncryptionMethod.FENCE:
        binary |= 1 << 2; // 第3位
        break;
      case EncryptionMethod.BASE64:
        binary |= 1 << 3; // 第4位
        break;
      case EncryptionMethod.SPLIT_PART:
        binary |= 1 << 4; // 第5位
        break;
    }
  }
  return binary;
}
  //错误信息提示
  void errormsg(String msg){
    _isStopRequested=true;
    _progressDialog.closeDialog();
    onDecryptionComplete?.call(msg);
    this.close();
  }
  //当停止后删除缓存文件
  void close() async {
    _cacheFile.clearAllCacheFiles();
  }
}
//解密
class myDecry implements StopMethod{
  List<String> _filePaths;//文件列表
  String _outputpath;//输出路径
  String _secret;//密码
  ProgressDialog _progressDialog;// 进度条
  bool _isStopRequested = false; // 中断标志
  ByteCache _cacheFile=new ByteCache("decry");
  final void Function(String)? onDecryptionComplete; // 回调函数
  //构造器
  myDecry(this._filePaths,
          this._outputpath,
          this._secret,
          this._progressDialog, 
          {this.onDecryptionComplete}) {}
  //解密遍历
  void decryptFiles() async{
    _progressDialog.setmax(_filePaths.length);
    int currentProgress = 0;
    await _cacheFile.initFilePath();
    _cacheFile.createCacheFile();
    await Future.forEach(_filePaths, (filePath) async {
      // 检查文件名是否以 .en 结尾
      if (!filePath.endsWith('.en')) {
        currentProgress++;
        _progressDialog.updata(currentProgress);
        return;
      }
      
      await decryptFile(filePath); // 确保每次加密操作完成后再继续下一个
      
      currentProgress++;// 更新进度条的当前进度
      _progressDialog.updata(currentProgress);
      if(_isStopRequested){
        this.close();
        _progressDialog.closeDialog();
        return;}
      _cacheFile.clearAllCacheFiles();
    });
    _progressDialog.closeDialog();
    onDecryptionComplete?.call("解密完成！"); 
}
  @override//终止加密，关闭流，并删除所有缓存文件
  void stop(bool isStop) {
    _isStopRequested = isStop;
    _progressDialog.closeDialog();
    this.close();
  }
  //解密文件处理        
  Future<void> decryptFile(String filePath) async{
    final file = File(filePath);
    if (!file.existsSync()) {errormsg('File does not exist: $filePath');}
    // 读取文件的第一个字节
    RandomAccessFile randomAccessFile = file.openSync(mode: FileMode.read);
    int binary = randomAccessFile.readByteSync();
    // 将二进制数转换回加密方法列表
    List<EncryptionMethod> encryptionMethods = binaryToEncryptionMethods(binary);
    // 创建初始缓存文件
    var cachefile = ByteCache("initial");
    await cachefile.initFilePath();
    cachefile.createCacheFile();
    var cacheoutput = cachefile.getOutputStream();
    try {
      randomAccessFile.setPositionSync(1); // 从第二个字节开始读取
      int fileSize = file.lengthSync() - 1;
      int bytesRead = 0;
      while (bytesRead < fileSize) {
        int bytesToRead = min(1024, fileSize - bytesRead);
        Uint8List buffer = randomAccessFile.readSync(bytesToRead);
        cacheoutput.add(buffer);
        bytesRead += bytesToRead;
      }
    } catch (e) {
      errormsg('Error copying file: $e');
    } finally {
      await randomAccessFile.close();
      await cacheoutput.close();
    }
    // 依次调用加密方法
    ByteCache resultCacheFile = cachefile;
    var flip_encryptionMethods=encryptionMethods.reversed.toList();
    int a=1;
    for (var method in flip_encryptionMethods) {
      resultCacheFile = await decryptContent(resultCacheFile, method,filePath);
      if (_isStopRequested){
        this.close();
        return;}
        a+=1;
    }
    // 提取文件名和后缀
    final fileName = path.basename(filePath);
    final baseFileName = path.basenameWithoutExtension(fileName);
    final extension = path.extension(fileName);
    String newFilePath = path.join(baseFileName);
    
    // 检查文件是否存在
    int spCount = 0;
    while (File(path.join(_outputpath,newFilePath)).existsSync()) {
        final outname=path.basenameWithoutExtension(newFilePath);
        final outextension= path.extension(newFilePath);
        spCount++;
        newFilePath = path.join('$outname${'_decry' * spCount}$outextension');
    } 
    newFilePath = path.join(_outputpath, newFilePath);  
    
    // 确保输出目录存在
    _ensureDirectoryExists(_outputpath);
    // 创建新文件并写入最终加密结果
    final outputFile = File(newFilePath);
    await outputFile.create();
    final outputStream2 = outputFile.openWrite();
    try {
      var inputStream2 = resultCacheFile.getInputStream();
      await inputStream2.pipe(outputStream2);
    } catch (e) {errormsg('Error writing to output file: $e');
    } finally {
      outputStream2.close();
    }
  }
  //解析头文件
  List<EncryptionMethod> binaryToEncryptionMethods(int binary) {
    List<EncryptionMethod> methods = [];
    if ((binary & (1 << 0)) != 0) methods.add(EncryptionMethod.ADD_RANDOM);
    if ((binary & (1 << 1)) != 0) methods.add(EncryptionMethod.AES);
    if ((binary & (1 << 2)) != 0) methods.add(EncryptionMethod.FENCE);
    if ((binary & (1 << 3)) != 0) methods.add(EncryptionMethod.BASE64);
    if ((binary & (1 << 4)) != 0) methods.add(EncryptionMethod.SPLIT_PART);
    return methods;
}
  //使用对应的加密方法
  Future<ByteCache> decryptContent(ByteCache cachefile, EncryptionMethod method,String filePath) async {
    if(_isStopRequested){
      return _cacheFile;
    }else{
    switch (method) {
      case EncryptionMethod.ADD_RANDOM:
        return  (await random_decry(cachefile));
      case EncryptionMethod.AES:
        return  (await aes_decry(cachefile));
      case EncryptionMethod.FENCE:
        return  (await fence_decry(cachefile));
      case EncryptionMethod.BASE64:
        return  (await base64_decry(cachefile));
      case EncryptionMethod.SPLIT_PART:
        return  (await split_decry(cachefile,filePath));
    }}
  }
  //去除随机数
  Future<ByteCache> random_decry(ByteCache cachefile) async {
    // 获取原缓存文件的路径
    String originalFilePath = cachefile.get_filePath();
    File originalFile = File(originalFilePath);
    // 获取原缓存文件的大小
    int fileSize = originalFile.lengthSync();
    if (!originalFile.existsSync()) {errormsg('缓存文件不存在: $originalFilePath');}
    // 创建一个新的缓存文件
    ByteCache newCacheFile = ByteCache("random_decry");
    await newCacheFile.initFilePath();
    newCacheFile.createCacheFile();
    IOSink newCacheOutputStream = newCacheFile.getOutputStream();

    // 使用滑动窗口读取原缓存文件的 1024 字节
    RandomAccessFile randomAccessFile = originalFile.openSync(mode: FileMode.read);
    try {
    int bytesRead = 0;
    while (bytesRead < fileSize) {
      int bytesToRead = min(1024, fileSize - bytesRead);
      Uint8List buffer = randomAccessFile.readSync(bytesToRead);
      // 每隔 2 位字节取前 1 位数据
      List<int> newBuffer = [];
      for (int i = 0; i < buffer.length; i += 2) {
        newBuffer.add(buffer[i]); // 当前字节数据
      }
      // 将处理后的内容写入新的缓存文件
      newCacheOutputStream.add(newBuffer);
      bytesRead += bytesToRead;
    }
  
  } catch (e) {
    await randomAccessFile.close();
    await newCacheOutputStream.close();
    errormsg("随机数去除失败:$e");
  }finally {
    // 关闭文件流
    await randomAccessFile.close();
    await newCacheOutputStream.close();
  }
  return newCacheFile;
}
  //AES解密
  Future<ByteCache> aes_decry(ByteCache cachefile) async {
  ByteCache newCacheFile = ByteCache("aes_decry");
  await newCacheFile.initFilePath();
  newCacheFile.createCacheFile();
  IOSink newCacheOutputStream = newCacheFile.getOutputStream();
  String encryptedFilePath = cachefile.get_filePath();
  File encryptedFile = File(encryptedFilePath);
  if (!encryptedFile.existsSync()) {
    errormsg('加密文件不存在: $encryptedFilePath');
  }
  // 读取整个加密数据（流式优化）
  RandomAccessFile randomAccessFile = encryptedFile.openSync(mode: FileMode.read);
  try {
    Uint8List iv = randomAccessFile.readSync(16);
    int fileSize = encryptedFile.lengthSync() - 16;
    int bytesRead = 0;
    Uint8List key = _generateKeyFromSecret(_secret);
    final encrypter = encrypt.Encrypter(encrypt.AES(encrypt.Key(key), mode: encrypt.AESMode.cbc,padding: null));
    Uint8List previousBlock = iv;
    while (bytesRead < fileSize) {
      int bytesToRead = min(1024, fileSize - bytesRead);
      Uint8List cipherChunk = randomAccessFile.readSync(bytesToRead);
      bytesRead += bytesToRead;
      // 解密当前块
      final decrypted = encrypter.decryptBytes(
        encrypt.Encrypted(cipherChunk),
        iv: encrypt.IV(previousBlock),
      );
      // 仅在文件末尾去除填充
      if (bytesRead >= fileSize) {
        Uint8List unpadded = _unpadBuffer(Uint8List.fromList(decrypted));
        newCacheOutputStream.add(unpadded);
      } else {
        newCacheOutputStream.add(decrypted);
      }

      previousBlock = cipherChunk.sublist(
        cipherChunk.length - 16,
        cipherChunk.length,
      );
    }

    
  } catch (e) {
    await randomAccessFile.close();
    await newCacheOutputStream.close();
    errormsg("AES解密失败:$e");
  } finally {
    await randomAccessFile.close();
    await newCacheOutputStream.close();
  }
  return newCacheFile;
}
  //增强填充验证
  Uint8List _unpadBuffer(Uint8List buffer) {
  if (buffer.isEmpty) return buffer;
  int paddingLength = buffer[buffer.length - 1];
  if (paddingLength < 1 || paddingLength > 16) {
    errormsg('无效填充长度: $paddingLength');
  }
  // 验证所有填充字节是否一致
  for (int i = buffer.length - paddingLength; i < buffer.length; i++) {
    if (buffer[i] != paddingLength) {errormsg('填充字节不一致');}
  }
  return buffer.sublist(0, buffer.length - paddingLength);
}
  //栏栅解密
  Future<ByteCache> fence_decry(ByteCache cachefile) async {
  
    // 获取原缓存文件的路径
    String originalFilePath = cachefile.get_filePath();
    File originalFile = File(originalFilePath);

    // 获取原缓存文件的大小
    int fileSize = originalFile.lengthSync();
    if (!originalFile.existsSync()) {
      errormsg('缓存文件不存在: $originalFilePath');
    }
    // 创建一个新的缓存文件
    ByteCache newCacheFile = ByteCache("fence_decry");
    await newCacheFile.initFilePath();
    newCacheFile.createCacheFile();
    IOSink newCacheOutputStream = newCacheFile.getOutputStream();

    // 使用滑动窗口读取原缓存文件的 1024 字节
    RandomAccessFile randomAccessFile = originalFile.openSync(mode: FileMode.read);
    try {
    int bytesRead = 0;
    Random random = Random();

    while (bytesRead < fileSize) {
      int bytesToRead = min(1024, fileSize - bytesRead);
      Uint8List buffer = randomAccessFile.readSync(bytesToRead);
      // 将处理后的内容写入新的缓存文件
      newCacheOutputStream.add(unfences(buffer));
      bytesRead += bytesToRead;
    }
  } catch (e) {
    // 关闭文件流
    await randomAccessFile.close();
    await newCacheOutputStream.close();
    errormsg("栅栏解密失败:$e");
  }finally {
    // 关闭文件流
    await randomAccessFile.close();
    await newCacheOutputStream.close();
  }
  return newCacheFile;
  }
  //base64解密
  Future<ByteCache> base64_decry(ByteCache cachefile) async {
    // 获取原缓存文件的路径
    String originalFilePath = cachefile.get_filePath();
    File originalFile = File(originalFilePath);
    // 获取原缓存文件的大小
    int fileSize = originalFile.lengthSync();
    if (!originalFile.existsSync()) {errormsg('缓存文件不存在: $originalFilePath');}
    // 创建一个新的缓存文件
    ByteCache newCacheFile = ByteCache("base64_decry");
    await newCacheFile.initFilePath();
    newCacheFile.createCacheFile();
    IOSink newCacheOutputStream = newCacheFile.getOutputStream();
    // 使用滑动窗口读取原缓存文件的 1020对应的1360 字节
    RandomAccessFile randomAccessFile = originalFile.openSync(mode: FileMode.read);
    try {
    int bytesRead = 0;
    List<int> buffer = [];
    while (bytesRead < fileSize) {
      int bytesToRead = min(1360, fileSize - bytesRead);
      buffer.addAll(randomAccessFile.readSync(bytesToRead));
      bytesRead += bytesToRead;
    }
    // 将读取的内容转换为字符串
    String base64EncodedString = utf8.decode(buffer);
    // 进行 Base64 解码
    List<int> decodedBytes = base64Decode(base64EncodedString);
    // 将解码后的内容写入新的缓存文件
    newCacheOutputStream.add(decodedBytes);
  } catch (e) {
    // 关闭文件流
    await randomAccessFile.close();
    await newCacheOutputStream.close();
    errormsg("base64解密失败:$e");
  }finally {
    await randomAccessFile.close();
    await newCacheOutputStream.close();
  }
  return newCacheFile;
}
  //分割解密
  Future<ByteCache> split_decry(ByteCache cachefile,String filePath) async {                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  
    // 获取原缓存文件的路径
    String originalFilePath = cachefile.get_filePath();
    File originalFile = File(originalFilePath);
    // 获取原缓存文件的大小
    int fileSize = originalFile.lengthSync();
    if (!originalFile.existsSync()) {errormsg('缓存文件不存在: $originalFilePath');}
    // 提取文件名和后缀
    final fileName = path.basename(filePath);
    final baseFileName = path.basenameWithoutExtension(fileName);
    final extension = path.extension(fileName);
    String splitFilePath = path.join(path.dirname(filePath), '$baseFileName.sp');
    
    // 检查分割文件是否存在
    File splitFile = File(splitFilePath);
    if (!splitFile.existsSync()) {errormsg('分割文件不存在: $splitFilePath');}
    // 创建一个新的缓存文件
    ByteCache newCacheFile = ByteCache("split_decry");
    await newCacheFile.initFilePath();
    newCacheFile.createCacheFile();
    IOSink newCacheOutputStream = newCacheFile.getOutputStream();

    // 读取分割文件的内容
    RandomAccessFile splitRandomAccessFile = splitFile.openSync(mode: FileMode.read);
    int splitFileSize = splitFile.lengthSync();
    int splitBytesRead = 0;
    try {
    while (splitBytesRead < splitFileSize) {
      int bytesToRead = min(1024, splitFileSize - splitBytesRead);
      Uint8List buffer = splitRandomAccessFile.readSync(bytesToRead);
      newCacheOutputStream.add(buffer);
      splitBytesRead += bytesToRead;
    }
     } catch (e) {
      await splitRandomAccessFile.close();
      errormsg("关闭分割文件失败:$e");
     }finally{
      await splitRandomAccessFile.close();
    }
    // 读取原文件的内容
    RandomAccessFile originalRandomAccessFile = originalFile.openSync(mode: FileMode.read);
    int originalBytesRead = 0;
    try{
    while (originalBytesRead < fileSize) {
      int bytesToRead = min(1024, fileSize - originalBytesRead);
      Uint8List buffer = originalRandomAccessFile.readSync(bytesToRead);
      newCacheOutputStream.add(buffer);
      originalBytesRead += bytesToRead;
    }
  } catch (e) {
    await originalRandomAccessFile.close();
    await newCacheOutputStream.close();
    errormsg("关闭原文件失败:$e");
  }finally{
    await originalRandomAccessFile.close();
    await newCacheOutputStream.close();
  }
  return newCacheFile;
}
  // 生成密钥
  Uint8List _generateKeyFromSecret(String secret) {
    String repeatedSecret = secret * ((32 / secret.length).ceil());// 如果密码长度不足 32 字节，则重复复制密码
    // 截取前 32 字节作为密钥
    return Uint8List.fromList(utf8.encode(repeatedSecret).sublist(0, 32));
}
  //栅栏解密具体实现
  Uint8List unfences(Uint8List buffer){
    Uint8List output= Uint8List(buffer.length);
    List<int> outqian= Uint8List(buffer.length*2);
    
    int star=0;
    for (int binaryDatum in buffer) {
      
      int wei8 = binaryDatum >> 0 & 1;
      int wei7 = binaryDatum >> 1 & 1;
      int wei6 = binaryDatum >> 2 & 1;
      int wei5 = binaryDatum >> 3 & 1;
      int wei4 = binaryDatum >> 4 & 1;
      int wei3 = binaryDatum >> 5 & 1;
      int wei2 = binaryDatum >> 6 & 1;
      int wei1 = binaryDatum >> 7 & 1;
      int cc = wei1*8 + wei2*4 + wei3*2  + wei4*1;
      int cc2 = wei5*8 + wei6*4 + wei7*2  + wei8*1;
      outqian[star] =cc;
      outqian[star+1] =cc2;
      star+=2;
    }
    int half = outqian.length~/2;
    for (int index=0;index<buffer.length;index++){
        
        int nb7 = outqian[index] % 2;
        int nb5 = (outqian[index] ~/ 2) % 2;
        int nb3 = (outqian[index] ~/ 4) % 2;
        int nb1 = (outqian[index] ~/ 8) % 2;
        int nb8 = outqian[half+index] % 2;
        int nb6 = (outqian[half+index] ~/ 2) % 2;
        int nb4 = (outqian[half+index] ~/ 4) % 2;
        int nb2 = (outqian[half+index] ~/ 8) % 2;
        int newnub = nb1*128+nb2*64+nb3*32+nb4*16+nb5*8+nb6*4+nb7*2+nb8*1;
        output[index] =newnub;
    }
    return output;
  }
  //确保输出目录存在
  void _ensureDirectoryExists(String directory) {
    if (!Directory(directory).existsSync()) {
      Directory(directory).createSync(recursive: true);
    }
}
  //当停止后删除缓存文件
  void close() async {
    _cacheFile.clearAllCacheFiles();
  }
  //错误信息提示
  void errormsg(String msg){
    _isStopRequested=true;
    _progressDialog.closeDialog();
    onDecryptionComplete?.call(msg);
    this.close();
  }
}
