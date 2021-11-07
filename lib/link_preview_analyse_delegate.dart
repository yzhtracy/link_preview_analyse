//抽象类，需要外部实现一些本地储存的功能
abstract class LinkPreviewSaveBox {
  //实现存入的方法
  Future<void> put(dynamic key, dynamic value);
  //实现清除的方法
  Future<int> clear();
  //实现关闭的方法
  Future<void> close();
  //实现删除的方法
  Future<void> delete(dynamic key);
  //实现读取的方法
  dynamic get(dynamic key, {dynamic defaultValue});
}
