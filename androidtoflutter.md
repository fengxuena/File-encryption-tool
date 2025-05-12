
# Flutter和原生安卓混合开发步骤
***

## 1.Android项目引入Flutter
- 在settings.grade中添加如下脚本：
```
setBinding(new Binding([gradle:this]))
evaluate(new File(
     settingsDir.parentFile,
     'flutter_module/.android/include_flutter.groovy'
))
```

- 其中flutter_module是flutter项目的路径，注意，flutter项目需要和安卓项目在同一个路径下。
- 打开app模组下的build.gradle，添加fulltter依赖，加入代码implementation project(‘:flutter’)，如下：
```
dependencies {
    implementation libs.appcompat
    implementation libs.material
    implementation libs.activity
    implementation libs.constraintlayout
    testImplementation libs.junit
    androidTestImplementation libs.ext.junit
    androidTestImplementation libs.espresso.core
    implementation project(':flutter')}
```

## 2.在Android项目中调用Flutter页面
- 创建 Flutter 页面
- 在 Flutter 项目中创建一个页面，例如 main.dart：
```
import 'package:flutter/material.dart';
void main() => runApp(MyApp());
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: Text('Flutter Page'),
        ),
        body: Center(
          child: Text('Hello from Flutter!'),),),);}}
```
## 3. 在 Android 中调用 Flutter 页面
- 在 Android 项目中，你可以通过 FlutterActivity 或 FlutterFragment 来启动 Flutter 页面。
- 使用 FlutterActivity在 Android 的 Activity 或 Fragment 中，使用 FlutterActivity 启动 Flutter 页面：
```
import io.flutter.embedding.android.FlutterActivity;
import android.content.Intent;
import android.os.Bundle;
import androidx.appcompat.app.AppCompatActivity;

public class MainActivity extends AppCompatActivity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        // 启动 FlutterActivity
        startActivity(
            FlutterActivity.createDefaultIntent(this)
        );
    }
}
```
- 使用 FlutterFragment,如果你想在 Fragment 中嵌入 Flutter 页面，可以使用 FlutterFragment：
```
<FrameLayout
    android:id="@+id/fragment_container"
    android:layout_width="match_parent"
    android:layout_height="match_parent"/>
```
## 4.在Flutter中调用Android页面从Flutter调用Android稍微复杂一点，我晚点会单独开一篇博客，并将链接贴出来。
***

## 5.遇到问题
- 在android工程引入Flutter依赖后，出现了如下问题：Caused by: org.gradle.api.internal.plugins.PluginApplicationException: Failed to apply plugin class ‘FlutterPlugin’.
解决方案：
### 5.1.打开Android project的settings.gradle修改repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)为repositoriesMode.set(RepositoriesMode.PREFER_PROJECT)
```
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_PROJECT)
    repositories {
        google()
        mavenCentral()
        jcenter() // Warning: this repository is going to shut down soon
    }
}
```
### 5.2. 打开Android project的build.gradle增加如下设置
```
allprojects {
    repositories {
        google()
        jcenter()
    }
}
```