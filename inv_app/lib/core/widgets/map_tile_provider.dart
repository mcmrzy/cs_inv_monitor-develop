import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

/// 磁盘缓存瓦片 Provider：复用 cached_network_image 的磁盘缓存
/// （默认 30 天过期、200MB 上限自动清理），重复浏览不重复下载、离线可用
class CachedNetworkTileProvider extends TileProvider {
  CachedNetworkTileProvider();

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return CachedNetworkImageProvider(getTileUrl(coordinates, options));
  }
}
