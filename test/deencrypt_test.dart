// my_math_test.dart
import 'dart:ffi';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:detool/deencrypt.dart';

void main() {
  group('add function', () {

    test('fence test', () {
      Uint8List buffer = Uint8List.fromList([0x1A, 0x2A, 0x3A, 0x4A, 0x5A]);
      Uint8List en = fences(buffer);
      Uint8List dn = unfences(en);
      print("buffer:"+buffer.toString());
      print("buffer:"+toBinaryStringList(buffer).toString());
      print("en    :"+en.toString());
      print("en    :"+toBinaryStringList(en).toString());
      print("dn    :"+dn.toString());
      print("dn    :"+toBinaryStringList(dn).toString());
    });

    test("method test", (){
      print("---------------------------------------");
      List<EncryptionMethod> methods = [
        EncryptionMethod.ADD_RANDOM,
        EncryptionMethod.AES,
        EncryptionMethod.FENCE,
        EncryptionMethod.BASE64,
      ];
      int mod=encryptionMethodsToBinary(methods);
      print("methods:"+toBinaryString(mod));
    });
  });
}
enum EncryptionMethod {
  ADD_RANDOM,
  AES,
  FENCE,
  BASE64,
  SPLIT_PART,
}
//头文件转二进制
int encryptionMethodsToBinary(List<EncryptionMethod> methods) {
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
//转二进制字符串
String toBinaryString(int value) {
  String binary = value.toRadixString(2);
  return binary.padLeft(8, '0');
}
//Uint8List转二进制字符串列表
List<String> toBinaryStringList(Uint8List buffer) {
  List<String> binaryStrings = [];
  for (int i = 0; i < buffer.length; i++) {
    String binaryString = toBinaryString(buffer[i]);
    binaryStrings.add(binaryString);
  }
  return binaryStrings;
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
  //print("outqian:"+outqian.toString());
  //print("outhou:"+outhou.toString());

  for (int i = 0; i < length; i++) {
    outlast[i] = outqian[i];
    outlast[i + length] = outhou[i];
  }
  //print("outlast:"+outlast.toString());

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
    //print("aa:"+aa.toString()+"   newnub:"+newnub.toString());
    output[aa] = newnub;
    aa+=1;
  }

  return output;
}
//栏栅解密具体实现
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