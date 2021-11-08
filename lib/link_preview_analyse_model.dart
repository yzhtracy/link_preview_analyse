import 'dart:isolate';

enum LinkPreviewType { web, image, video, audio }

class LinkPreviewInfo {
  //标题
  String title;
  //页面的小图标
  String icon;
  //页面的描述文字
  String description;
  //页面类型
  LinkPreviewType type = LinkPreviewType.web;
  //页面的内容链接(图片或视频)
  String mediaUrl;
  //原请求地址
  String redirectUrl;

  //上次加载的时间
  int loadTime;

  Map<dynamic, dynamic> toMap() {
    final Map<dynamic, dynamic> map = {
      "title": title,
      "icon": icon,
      "description": description,
      "type": type.index,
      "mediaUrl": mediaUrl,
      "redirectUrl": redirectUrl,
      "loadTime": loadTime
    };
    return map;
  }

  static LinkPreviewInfo fromMap(Map<dynamic, dynamic> map) {
    final LinkPreviewInfo info = LinkPreviewInfo();
    info.title = map["title"];
    info.icon = map["icon"];
    info.description = map["description"];
    info.mediaUrl = map["mediaUrl"];
    info.redirectUrl = map["redirectUrl"];
    info.loadTime = map["loadTime"];
    final int typeIndex = map["type"];
    info.type = LinkPreviewType.values[typeIndex];
    return info;
  }
}

class LinkPreviewTaskModel {
  LinkPreviewInfo info = LinkPreviewInfo();
  String link = "";
  SendPort port;
  //分配的webView
  bool isRun = false;
  String originIcon;
}
