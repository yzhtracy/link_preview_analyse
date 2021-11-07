import 'dart:isolate';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'link_preview_analyse_delegate.dart';
import 'link_preview_analyse_model.dart';

class LinkPreviewAnalyse {
  //单例
  static var shared = LinkPreviewAnalyse();

  static final LinkPreviewAnalyse _instance = LinkPreviewAnalyse._internal();

  factory LinkPreviewAnalyse() => _instance;
  //解析失败时发送的字符串
  var _errorString = "error";

  //数据库的名字
  var _boxName = "link_preview_analyse_box_name";

  //最大的webView数量
  var maxWebViewNumber = 3;

  //单个链接的最大等待时间
  var maxWaitTimeSecond = 5;

  //是否打开日志
  var isOpenLog = false;

  //存放webVewList的数组
  List<HeadlessWebViewTool> _webViewList = [];

  //存放分析任务的池子
  List<LinkPreviewTaskModel> _taskPool = [];

  //解析记录过期的小时数
  int _saveHour;

  //用来储存的box
  LinkPreviewSaveBox _box;

  LinkPreviewAnalyse._internal() {
    init();
  }

  //防止多次webView进度完成回调
  var _progressLock = false;

  init() async {
    _checkStatus();
  }

  //设置储存的代理，如果不设置就不会有缓存
  void configSaveDelegate(LinkPreviewSaveBox saveBox, int saveHour) {
    _saveHour = saveHour;
    _box = saveBox;
    devLog("设置了储存的代理");
  }

  //读取链接
  static Future<LinkPreviewInfo> analyseLink(String link) async {
    if (shared._box != null) {
      devLog("box有值,先找之前的记录");
      Map<dynamic, dynamic> map = await shared._box.get(link);
      if (map != null) {
        LinkPreviewInfo history = LinkPreviewInfo.fromMap(map);
        devLog("找出了之前解析记录");
        if (history.loadTime + shared._saveHour * 60 * 60 * 1000 >
            DateTime.now().millisecondsSinceEpoch) {
          devLog("解析记录没有过期，直接用");
          return history;
        } else {
          devLog("解析记录过期了重新读取");
          await shared._box.delete(link);
        }
      } else {
        devLog("没有找到之前的解析记录");
      }
    }
    var taskModel = LinkPreviewTaskModel();
    ReceivePort receivePort = ReceivePort();
    taskModel.link = link;
    taskModel.port = receivePort.sendPort;
    shared._setupTask(taskModel);
    var result = await receivePort.first;
    if (result == shared._errorString) {
      throw "link解析失败";
    }
    LinkPreviewInfo info = result;
    return info;
  }

  //每五秒检查一次下载的进度情况
  void _checkStatus() {
    for (var i = 0; i < _webViewList.length; i++) {
      var web = _webViewList[i];
      if (web.taskModel != null) {
        devLog("webLink = ${web.taskModel.link},progress = ${web.progress}");
        //如果5秒请求进度没有改变就直接报错
        if (web.oldLink == web.taskModel.link &&
            web.progress == web.oldProgress) {
          devLog("超过最大等待时间webView没有进度变化，返回错误信号");
          _sendError(web);
        } else {
          web.oldLink = web.taskModel.link;
          web.oldProgress = web.progress;
        }
      }
    }
    Future.delayed(Duration(seconds: maxWaitTimeSecond), () async {
      _checkStatus();
    });
  }

  //对加进来的任务进行分配
  _setupTask(LinkPreviewTaskModel model) async {
    _taskPool.add(model);
    HeadlessWebViewTool webViewTool;
    //把任务分配给容器里闲着的webView
    for (var web in _webViewList) {
      if (!web.isLock) {
        webViewTool = web;
      }
    }
    //当没有空闲且最大webView数没到上限就创建一个
    if (webViewTool == null && _webViewList.length < maxWebViewNumber) {
      devLog(
          "最大webView数量$maxWebViewNumber ,当前${_webViewList.length}。还有空间就再创建一个");
      webViewTool = HeadlessWebViewTool();
      _webViewList.add(webViewTool);
    }

    //如果分配下去就立马执行，没有就等待
    if (webViewTool != null) {
      devLog("当前有闲置的webView可以分配,直接开始请求");
      _webViewLoadLink(webViewTool, model);
    } else {
      devLog("当前没有闲置的webView，开始排队");
    }
  }

  //将解析任务和webView进行绑定
  _webViewLoadLink(
      HeadlessWebViewTool webView, LinkPreviewTaskModel model) async {
    var index = _webViewList.indexOf(webView);
    devLog("开始绑定数组中的第$index个webView,link=${model.link}");
    webView.isLock = true;
    model.isRun = true;
    webView.taskModel = model;
    webView.progress = 0;
    webView.baseWebView = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(url: Uri.parse(model.link)),
        onProgressChanged: (c, p) async {
          devLog("进度====p$p ,url:(${webView.taskModel.link})");
          webView.progress = p;
          if (p == 100 && !_progressLock) {
            _progressLock = true;
            devLog("收到了回调 准备分析");
            _startAnalyse(c, webView, webView.taskModel);
          } else {
            _progressLock = false;
          }
        },
        onLoadStart: (c, u) {
          devLog("开始加载");
          var icon = "${u.origin}/favicon.ico";
          if (webView.taskModel.originIcon == null) {
            webView.taskModel.originIcon = icon;
            devLog("没有发生跳转行为前的原始icon = $icon");
          }
        },
        onLoadError: (c, url, code, message) {
          if (message.contains("URL_SCHEME")) {
            return;
          }
          devLog("发生错误:$message,link:(${model.link})");
          _sendError(webView);
        });
    devLog("新建webView开始请求：url(${model.link})");
    await webView.baseWebView.run();
  }

  //对任务的Futrue发错误信号
  void _sendError(HeadlessWebViewTool webView) {
    webView.taskModel.port.send(_errorString);
    webView.isLock = false;
    _taskPool.remove(webView.taskModel);
    webView.baseWebView.dispose();
    webView.baseWebView = null;
    _nextTask(webView);
  }

  //对取回的信息进行分析
  Future<void> _startAnalyse(InAppWebViewController controller,
      HeadlessWebViewTool webView, LinkPreviewTaskModel taskModel) async {
    devLog("开始分析${taskModel.link}");
    try {
      var model = LinkPreviewInfo();
      model.redirectUrl = taskModel.link;
      model.icon = taskModel.originIcon;
      model.mediaUrl = null;
      var metas = await controller.getMetaTags();
      if (metas.length <= 1) {
        devLog("非标准网页形式无法解析 url:${taskModel.link}");
        taskModel.port.send(_errorString);
      } else {
        for (var tag in metas) {
          if (tag.name == "description") {
            model.description = tag.content;
          }
          if (tag.name == "") if (tag.content.contains(".jpg") ||
              tag.content.contains(".png")) {
            model.mediaUrl = tag.content;
          }
          if (tag.name == "title") {
            model.title = tag.content;
          }
          // devLog("atts的数量 = ${tag.attrs.length}  map=${tag.toMap()}");
          for (var maps in tag.attrs) {
            // devLog("maps = $maps");
            if (maps.name == "property" && maps.value == "og:image") {
              model.mediaUrl = tag.content;
            }
            if (maps.name == "property" && maps.value == "og:title") {
              model.title = tag.content;
            }
          }
        }

        if (model.title == null) {
          try {
            model.title = await controller.getTitle();
          } catch (e) {
            model.title = null;
          }
        }
        devLog(
            "解析出了结果:icons = ${model.icon},title = ${model.title} ,des = ${model.description},content = ${model.mediaUrl}");
        taskModel.info = model;
        if (shared._box != null) {
          devLog("将数据缓存到本地:link=${taskModel.link}");
          model.loadTime = DateTime.now().millisecondsSinceEpoch;
          shared._box.put(taskModel.link, model.toMap());
        }
        taskModel.port.send(model);
        devLog("已对外发送成功解析的数据");
      }
    } catch (e) {
      devLog("发生错误:${e.toString()}，url:${taskModel.link}");
      taskModel.port.send(_errorString);
    }
    webView.isLock = false;
    _taskPool.remove(taskModel);
    devLog("解析完成，开始下一个");
    webView.baseWebView.dispose();
    webView.baseWebView = null;
    webView.taskModel = null;
    _nextTask(webView);
  }

  //webView处理完当前任务，开始进行下一个任务的分配
  _nextTask(HeadlessWebViewTool webView) async {
    for (var task in _taskPool) {
      if (task.isRun == false) {
        _webViewLoadLink(webView, task);
        return;
      }
    }
  }

  //输出日志
  static void devLog(String str) {
    if (shared.isOpenLog) {
      print("LPA======$str + ${DateTime.now().toString()}");
    }
  }
}

class HeadlessWebViewTool {
  //当前请求的webView
  HeadlessInAppWebView baseWebView;
  //当前webView执行的任务
  LinkPreviewTaskModel taskModel;
  //当前的进度
  var progress = 0;
  //是否能被操作
  var isLock = false;
  //之前请求的link(用于容错)
  String oldLink = "";
  //之前请求的进度(用于容错)
  int oldProgress = 0;
}
