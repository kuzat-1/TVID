import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:yandex_mobileads/mobile_ads.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';

bool firebaseReady = false;
const String appVersion = '1.3.5';
const String storeUrl =
    'https://play.google.com/store/apps/details?id=su.layn.app';
const String adminApiBase = 'https://kuzat.ru';

String thumbProxy(String url) {
  final String u = url.trim();
  if (u.isEmpty) return u;
  if (u.startsWith('$adminApiBase/api/thumb')) return u;
  return '$adminApiBase/api/thumb?url=${Uri.encodeComponent(u)}';
}
final AdminStore adminStore = AdminStore();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  } catch (_) {}
  try {
    await YandexAds.initialize();
  } catch (_) {}
  try {
    await Firebase.initializeApp();
    firebaseReady = true;
  } catch (_) {}
  runApp(const StreamApp());
}

const Color bgColor = Color(0xFF0D0E12);
const Color surfaceColor = Color(0xFF1A1C23);
const Color primaryPurple = Color(0xFF5B41D9);
const Color secondaryPurple = Color(0xFF8C7AE6);
const Color navIconIdle = Color(0xFF8E8E93);
const Color textPrimary = Color(0xFFFFFFFF);
const Color textSecondary = Color(0xFFA4B0BE);
const Color textMuted = Color(0xFF747D8C);
const Color placeholderPurple = Color(0xFF241D4B);

const List<Color> appBgGradient = [
  Color(0xFF0D0D0D),
  Color(0xFF151027),
  Color(0xFF0D0D0D),
];

const List<String> categories = [];

// ─── Источник видео: только бэкенд kuzat.ru (без прямых запросов к VK) ───
const String interestsPrefsKey = 'user_interests_v1';
const int maxInterests = 10;
const String lastCategoryPrefsKey = 'last_selected_category';

const Set<String> noiseWords = {
  'видео',
  'смотреть',
  'онлайн',
  'online',
  'video',
  'official',
  'music',
  'full',
  'trailer',
  'трейлер',
  'часть',
  'сезон',
  'season',
  'серия',
  'episode',
  'выпуск',
  'эфир',
  'new',
  'top',
  'best',
  'лучшее',
  'watch',
  'movie',
  'song',
  'фильм',
  'сериал',
  'клип',
  'юмор',
  'тренды',
  'тренд',
  'новинки',
  'новинка',
  'подборка',
  'сборник',
};

List<String> extractKeywords(String title) {
  final Set<String> tokens = RegExp(r'[a-zа-яё0-9]+')
      .allMatches(title.toLowerCase())
      .map((m) => m.group(0)!)
      .where((t) => t.length > 3 && !noiseWords.contains(t))
      .toSet();
  return tokens.take(2).toList();
}

bool isContentRestricted(Map<String, dynamic> item) {
  final dynamic cr = item['content_restricted'];
  if (cr is int) return cr != 0;
  if (cr is bool) return cr;
  if (cr is Map && cr.isNotEmpty) return true;
  if (item['is_private'] == 1) return true;
  if (item['can_play'] == 0) return true;
  if (item['adult'] == 1 || item['adult'] == true) return true;
  return false;
}

// ─── СТРОГО: политический контент запрещён ───
const List<String> bannedPoliticalWords = [
  'политик',
  'новости',
  'новость',
  'новост',
  'выборы',
  'выбор',
  'президент',
  'правительство',
  'война',
  'митинг',
  'чиновник',
  'политолог',
  'дебаты',
  'депутат',
  'парламент',
  'госдума',
  'оппозиц',
  'протест',
  'революц',
  'власть',
  'министр',
  'губернатор',
  'кремль',
  'путин',
  'зеленский',
  'байден',
  'трамп',
  'навальн',
  'мобилизац',
  'фронт',
  'армия',
  'военнослуж',
  'конфликт',
  'пропаганд',
  'агитац',
  'референдум',
  'кандидат',
  'партия',
  'единая россия',
  'лдпр',
  'кпрф',
  'коррупц',
  'взятка',
  'спецслужб',
  'росгвардия',
  'нато',
  'санкци',
  'дипломат',
  'посольство',
  'переворот',
  'импичмент',
  'инаугурац',
  'мэр',
  'префект',
  'хоким',
  'siyosat',
  'prezident',
  'hukumat',
  'urush',
  'saylov',
  'miting',
  'hokim',
  'deputat',
  'parlament',
  'partiya',
  'muxolifat',
  'inqilob',
  'hokimiyat',
  'politic',
  'election',
  'government',
  'parliament',
  'minister',
  'revolution',
  'military',
  'senate',
  'congress',
  'white house',
  'сво',
  'всу',
  'оон',
  'дума',
  'мвд',
  'фсб',
];

bool isPoliticalContent(String text) {
  final String t = text.toLowerCase();
  final Set<String> tokens = RegExp(r'[a-zа-яё0-9]+')
      .allMatches(t)
      .map((m) => m.group(0)!)
      .toSet();
  for (final String w in bannedPoliticalWords) {
    if (w.length <= 4) {
      if (tokens.contains(w)) return true;
    } else {
      if (t.contains(w)) return true;
    }
  }
  return false;
}

String formatDuration(int seconds) {
  if (seconds <= 0) return 'VK Video';
  final int m = seconds ~/ 60;
  final int s = seconds % 60;
  if (m >= 60) {
    final int h = m ~/ 60;
    final int mm = m % 60;
    return '$h:${mm.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '$m:${s.toString().padLeft(2, '0')}';
}

String formatViews(dynamic views) {
  final int v = views is int ? views : int.tryParse('$views') ?? 0;
  if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M Views';
  if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K Views';
  if (v > 0) return '$v Views';
  return 'VK Video';
}

class VideoItem {
  final String title;
  final String author;
  final String stats;
  final String views;
  final String duration;
  final String thumb;
  final String embedUrl;
  final String player;
  final int durationSec;
  final bool vertical;
  final String genre;
  final bool direct;
  const VideoItem({
    required this.title,
    required this.author,
    required this.stats,
    required this.views,
    required this.duration,
    required this.durationSec,
    required this.thumb,
    required this.embedUrl,
    required this.player,
    this.vertical = false,
    this.genre = '',
    this.direct = false,
  });

  factory VideoItem.fromVk(Map<String, dynamic> item) {
    final dynamic id = item['id'];
    final dynamic ownerId = item['owner_id'];
    final String title = '${item['title'] ?? 'Без названия'}';
    final int duration = item['duration'] is int
        ? item['duration'] as int
        : int.tryParse('${item['duration'] ?? 0}') ?? 0;
    String thumb = '';
    for (final String k in ['photo_800', 'photo_320', 'photo_130', 'photo_80']) {
      final dynamic u = item[k];
      if (u is String && u.isNotEmpty) {
        thumb = u;
        break;
      }
    }
    if (thumb.isEmpty && item['image'] is List && (item['image'] as List).isNotEmpty) {
      final dynamic last = (item['image'] as List).last;
      if (last is Map && last['url'] is String) thumb = last['url'] as String;
    }
    if (thumb.isEmpty) {
      thumb =
          'https://images.unsplash.com/photo-1517841905240-472988babdf9?w=800&auto=format&fit=crop';
    }
    final dynamic accessKey = item['access_key'];
    final String hash = accessKey is String ? accessKey : '';
    final dynamic playerRaw = item['player'];
    final String player =
        playerRaw is String && playerRaw.isNotEmpty ? playerRaw : '';
    final String viewsLabel = formatViews(item['views']);
    final String durationLabel = duration > 0 ? formatDuration(duration) : '';
    final int w = item['width'] is int
        ? item['width'] as int
        : int.tryParse('${item['width'] ?? 0}') ?? 0;
    final int h = item['height'] is int
        ? item['height'] as int
        : int.tryParse('${item['height'] ?? 0}') ?? 0;
    final String keyParams =
        hash.isNotEmpty ? '&hash=$hash&access_key=$hash' : '';
    return VideoItem(
      title: title,
      author: 'VK Video',
      stats: durationLabel.isNotEmpty
          ? '$viewsLabel • $durationLabel'
          : viewsLabel,
      views: viewsLabel,
      duration: durationLabel,
      durationSec: duration,
      thumb: thumb,
      embedUrl:
          'https://vk.com/video_ext.php?oid=$ownerId&id=$id$keyParams',
      player: player,
      vertical: h > 0 && w > 0 ? h > w : false,
      genre: '',
      direct: false,
    );
  }

  String _vkParam(String name) {
    final RegExpMatch? m =
        RegExp('[?&]$name=([^&]+)').firstMatch(embedUrl);
    return m?.group(1) ?? '';
  }

  String get vkOid => _vkParam('oid');
  String get vkId => _vkParam('id');
  String get vkHash => _vkParam('hash');
  String get videoKey => '${vkOid}_$vkId';

  VideoItem copyWith({String? title, String? thumb}) {
    return VideoItem(
      title: title ?? this.title,
      author: author,
      stats: stats,
      views: views,
      duration: duration,
      durationSec: durationSec,
      thumb: thumb ?? this.thumb,
      embedUrl: embedUrl,
      player: player,
      vertical: vertical,
      genre: genre,
      direct: direct,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is VideoItem && other.embedUrl == embedUrl;

  @override
  int get hashCode => embedUrl.hashCode;
}

Future<http.Response> _getWithFallback(Uri primary, Duration timeout) async {
  Object? lastError;
  for (int attempt = 0; attempt < 3; attempt++) {
    try {
      final http.Response resp =
          await http.get(primary).timeout(timeout);
      if (resp.statusCode == 200) return resp;
      lastError = Exception('HTTP ${resp.statusCode}');
    } catch (e) {
      lastError = e;
    }
    if (attempt < 2) {
      await Future.delayed(Duration(milliseconds: 400 * (attempt + 1)));
    }
  }
  throw lastError ?? Exception('network failed');
}

String vkDirectHtml(String streamUrl, bool autoplay) {
  return '''
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<style>
html,body{margin:0;padding:0;background:#000;height:100%;overflow:hidden;}
#vplayer{position:absolute;top:0;left:0;width:100%;height:100%;background:#000;}
</style>
</head>
<body>
<video id="vplayer" src="$streamUrl" controls playsinline ${autoplay ? 'autoplay' : ''}></video>
<script>
var dv = document.getElementById('vplayer');
dv.addEventListener('error', function() { try { console.log('VK_PLAYER_ERROR'); } catch (e) {} });
function vkPause() { try { dv.pause(); return 'ok'; } catch (e) { return 'err'; } }
function vkPlay() { try { dv.muted = false; dv.volume = 1; var p = dv.play(); if (p) { p.catch(function(e){}); } return 'ok'; } catch (e) { return 'err'; } }
function vkUnmute() { try { dv.muted = false; dv.volume = 1; return 'ok'; } catch (e) { return 'err'; } }
</script>
</body>
</html>
''';
}

String vkPlayerHtml(VideoItem v, bool autoplay) {
  final String hash = v.vkHash;
  final String auto = autoplay ? '1' : '0';
  final String keyParams =
      hash.isNotEmpty ? '&hash=$hash&access_key=$hash' : '';
  String base = v.player.isNotEmpty ? v.player : v.embedUrl;
  if (!base.contains('video_ext.php')) {
    base = v.embedUrl;
  }
  final String sep = base.contains('?') ? '&' : '?';
  final String src =
      '$base${sep}hd=2&autoplay=$auto&js_api=1$keyParams'
          .replaceAll('&', '&amp;');
  return '''
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<style>
html,body{margin:0;padding:0;background:#000;height:100%;overflow:hidden;}
#vkframe{position:absolute;top:0;left:0;width:100%;height:100%;border:0;}
</style>
<script src="https://vk.com/js/api/videoplayer.js"></script>
</head>
<body>
<iframe id="vkframe"
src="$src"
allow="autoplay; encrypted-media; fullscreen; picture-in-picture;" allowfullscreen></iframe>
<script>
var vkPlayer = null;
function vkInitPlayer() {
  try {
    if (window.VK && VK.VideoPlayer && !vkPlayer) {
      vkPlayer = VK.VideoPlayer(document.getElementById('vkframe'));
      vkPlayer.on('started', function() { try { vkPlayer.unmute(); vkPlayer.setVolume(1); } catch (e) {} });
      vkPlayer.on('resumed', function() { try { vkPlayer.unmute(); vkPlayer.setVolume(1); } catch (e) {} });
      vkPlayer.on('inited', function() { try { vkPlayer.unmute(); vkPlayer.setVolume(1); } catch (e) {} });
      vkPlayer.on('error', function() { try { console.log('VK_PLAYER_ERROR'); } catch (e) {} });
    }
  } catch (e) {}
}
if (document.readyState === 'complete') { vkInitPlayer(); }
window.addEventListener('load', vkInitPlayer);
setTimeout(vkInitPlayer, 1500);
setTimeout(vkInitPlayer, 4000);
function vkPause() { try { if (vkPlayer) { vkPlayer.pause(); return 'ok'; } } catch (e) { return 'err'; } return 'noplayer'; }
function vkPlay() { try { if (vkPlayer) { try { vkPlayer.unmute(); vkPlayer.setVolume(1); } catch (e) {} vkPlayer.play(); return 'ok'; } } catch (e) { return 'err'; } return 'noplayer'; }
function vkUnmute() { try { if (vkPlayer) { vkPlayer.unmute(); vkPlayer.setVolume(1); return 'ok'; } } catch (e) { return 'err'; } return 'noplayer'; }
</script>
</body>
</html>
''';
}

const List<VideoItem> fallbackPlaylist = [];

class YandexFeedAd extends StatefulWidget {
  final String blockId;
  final int maxWidth;
  final double height;
  final bool showLabel;
  const YandexFeedAd(
      {super.key,
      required this.blockId,
      required this.maxWidth,
      this.height = 250,
      this.showLabel = true});

  @override
  State<YandexFeedAd> createState() => _YandexFeedAdState();
}

class _YandexFeedAdState extends State<YandexFeedAd> {
  BannerAd? _banner;
  bool _loaded = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    try {
      _banner = BannerAd(
        adSize: BannerAdSize.inline(
            width: widget.maxWidth,
            maxHeight: widget.height.round()),
      );
      _banner!.loadStateStream.listen((state) {
        if (!mounted) return;
        if (state is BannerAdLoadStateLoaded) {
          setState(() => _loaded = true);
        } else if (state is BannerAdLoadStateError) {
          setState(() => _failed = true);
        }
      });
      _banner!.load(AdRequest(adUnitId: widget.blockId));
    } catch (_) {
      _failed = true;
    }
  }

  @override
  void dispose() {
    try {
      _banner?.destroy();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: widget.height,
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: _loaded && _banner != null
                  ? AdWidget(bannerAd: _banner!)
                  : const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: secondaryPurple,
                          strokeWidth: 2,
                        ),
                      ),
                    ),
            ),
          ),
          if (widget.showLabel) const SizedBox(height: 8),
          if (widget.showLabel)
            const Text(
              'Реклама • Яндекс',
              style: TextStyle(fontSize: 12, color: textMuted),
            ),
        ],
      ),
    );
  }
}

class HtmlFeedCard extends StatefulWidget {
  final int maxWidth;
  const HtmlFeedCard({super.key, required this.maxWidth});

  @override
  State<HtmlFeedCard> createState() => _HtmlFeedCardState();
}

class _HtmlFeedCardState extends State<HtmlFeedCard> {
  bool _hidden = false;

  Future<void> _report() async {
    try {
      await http
          .post(
            Uri.parse('$adminApiBase/api/admin/ads/report'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'reason': 'feed html report'}),
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Спасибо! Жалоба отправлена.'),
        backgroundColor: surfaceColor,
      ),
    );
    setState(() => _hidden = true);
  }

  void _menu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161820),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.visibility_off_outlined,
                    color: navIconIdle),
                title: const Text('Не интересно',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _hidden = true);
                },
              ),
              ListTile(
                leading: const Icon(Icons.flag_outlined,
                    color: Colors.orange),
                title: const Text('Пожаловаться',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  _report();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_hidden) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 250,
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: InAppWebView(
                      initialData: InAppWebViewInitialData(
                        data: adminStore.customHtml,
                      ),
                      initialSettings: InAppWebViewSettings(
                        javaScriptEnabled: true,
                        domStorageEnabled: true,
                        mediaPlaybackRequiresUserGesture: false,
                        transparentBackground: true,
                      ),
                      shouldOverrideUrlLoading:
                          (controller, navigationAction) async {
                        final Uri? uri =
                            navigationAction.request.url;
                        if (uri == null) {
                          return NavigationActionPolicy.CANCEL;
                        }
                        if (uri.scheme == 'data' ||
                            uri.scheme == 'about' ||
                            uri.scheme == 'blob') {
                          return NavigationActionPolicy.ALLOW;
                        }
                        try {
                          await launchUrl(uri,
                              mode: LaunchMode
                                  .externalApplication);
                        } catch (_) {}
                        return NavigationActionPolicy.CANCEL;
                      },
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: GestureDetector(
                      onTap: _menu,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color:
                                  Colors.white.withOpacity(0.25)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'ⓘ',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700),
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Реклама',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ),
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

class HtmlReelsCard extends StatefulWidget {
  const HtmlReelsCard({super.key});

  @override
  State<HtmlReelsCard> createState() => _HtmlReelsCardState();
}

class _HtmlReelsCardState extends State<HtmlReelsCard> {
  bool _hidden = false;

  Future<void> _report() async {
    try {
      await http
          .post(
            Uri.parse('$adminApiBase/api/admin/ads/report'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'reason': 'reels html report'}),
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Спасибо! Жалоба отправлена.'),
        backgroundColor: surfaceColor,
      ),
    );
    setState(() => _hidden = true);
  }

  void _menu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161820),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.visibility_off_outlined,
                    color: navIconIdle),
                title: const Text('Не интересно',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _hidden = true);
                },
              ),
              ListTile(
                leading: const Icon(Icons.flag_outlined,
                    color: Colors.orange),
                title: const Text('Пожаловаться',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  _report();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_hidden) return Container(color: Colors.black);
    final double reelsPad = MediaQuery.of(context).padding.bottom;
    return Container(
      color: Colors.black,
      child: SafeArea(
        top: true,
        bottom: true,
        child: Stack(
          children: [
            Positioned.fill(
              child: InAppWebView(
                initialData: InAppWebViewInitialData(
                  data: adminStore.customHtml,
                ),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  domStorageEnabled: true,
                  mediaPlaybackRequiresUserGesture: false,
                  transparentBackground: true,
                ),
                shouldOverrideUrlLoading:
                    (controller, navigationAction) async {
                  final Uri? uri = navigationAction.request.url;
                  if (uri == null) {
                    return NavigationActionPolicy.CANCEL;
                  }
                  if (uri.scheme == 'data' ||
                      uri.scheme == 'about' ||
                      uri.scheme == 'blob') {
                    return NavigationActionPolicy.ALLOW;
                  }
                  try {
                    await launchUrl(uri,
                        mode: LaunchMode.externalApplication);
                  } catch (_) {}
                  return NavigationActionPolicy.CANCEL;
                },
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: GestureDetector(
                onTap: _menu,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: Colors.white.withOpacity(0.25)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'ⓘ',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700),
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Реклама',
                        style: TextStyle(
                            color: Colors.white, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 24 + reelsPad,
              left: 0,
              right: 0,
              child: const IgnorePointer(
                child: Center(
                  child: Text(
                    'Свайпните вверх, чтобы продолжить',
                    style: TextStyle(
                        fontSize: 13,
                        color: textSecondary,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PlayerAdBanner extends StatefulWidget {
  final String mode;
  final String html;
  final String blockId;
  final int maxWidth;
  const PlayerAdBanner({
    super.key,
    required this.mode,
    required this.html,
    required this.blockId,
    required this.maxWidth,
  });

  @override
  State<PlayerAdBanner> createState() => _PlayerAdBannerState();
}

class _PlayerAdBannerState extends State<PlayerAdBanner> {
  int _left = 15;
  bool _closed = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_left <= 1) {
        t.cancel();
        setState(() => _left = 0);
      } else {
        setState(() => _left--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_closed) return const SizedBox.shrink();
    return Container(
      height: 132,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.78),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            Positioned.fill(
              child: widget.mode == 'yandex'
                  ? YandexFeedAd(
                      blockId: widget.blockId,
                      maxWidth: widget.maxWidth,
                      height: 132,
                      showLabel: false,
                    )
                  : InAppWebView(
                      initialData: InAppWebViewInitialData(
                        data: widget.html,
                      ),
                      initialSettings: InAppWebViewSettings(
                        javaScriptEnabled: true,
                        domStorageEnabled: true,
                        mediaPlaybackRequiresUserGesture: false,
                        transparentBackground: true,
                      ),
                      shouldOverrideUrlLoading:
                          (controller, navigationAction) async {
                        final Uri? uri =
                            navigationAction.request.url;
                        if (uri == null) {
                          return NavigationActionPolicy.CANCEL;
                        }
                        if (uri.scheme == 'data' ||
                            uri.scheme == 'about' ||
                            uri.scheme == 'blob') {
                          return NavigationActionPolicy.ALLOW;
                        }
                        try {
                          await launchUrl(uri,
                              mode: LaunchMode
                                  .externalApplication);
                        } catch (_) {}
                        return NavigationActionPolicy.CANCEL;
                      },
                    ),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: GestureDetector(
                onTap: _left <= 0
                    ? () => setState(() => _closed = true)
                    : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: Colors.white.withOpacity(0.25)),
                  ),
                  child: Text(
                    _left > 0 ? '$_left' : '✕',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
            const Positioned(
              top: 8,
              left: 10,
              child: Text(
                'Реклама',
                style: TextStyle(
                    color: Colors.white70, fontSize: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AdminStore {
  Set<String> blacklist = {};
  Map<String, Map<String, dynamic>> custom = {};
  bool yandexEnabled = false;
  int feedAdEvery = 5;
  int reelsAdEvery = 6;
  String feedBlockId = 'demo-banner-yandex';
  String reelsBlockId = 'demo-interstitial-yandex';
  String latestVersion = appVersion;
  bool forceUpdate = false;
  String adminPass = '123456tanho';
  bool customHtmlEnabled = false;
  String customHtml = '';
  String customHtmlPlacement = 'player';
  String vkToken = '';
  String videoSource = 'vkapi';
  String vkAppId = '';
  String playerAdMode = 'off';
  int playerAdEvery = 4;
  bool htmlPlayer = false;
  bool htmlOpen = false;
  bool htmlFeed = false;
  bool htmlReels = false;
  String userVkToken = '';
  String userVkId = '';
  int localViews = 0;
  int fsUsers = 0;
  int fsViews = 0;

  bool isBlocked(String key) => blacklist.contains(key);
  bool isHidden(String key) => custom[key]?['is_hidden'] == true;

  VideoItem apply(VideoItem v) {
    final Map<String, dynamic>? c = custom[v.videoKey];
    if (c == null) return v;
    final String t = '${c['title'] ?? ''}';
    final String th = '${c['thumb'] ?? ''}';
    if (t.isEmpty && th.isEmpty) return v;
    return v.copyWith(
      title: t.isNotEmpty ? t : null,
      thumb: th.isNotEmpty ? th : null,
    );
  }

  List<VideoItem> filterFeed(List<VideoItem> src) {
    final List<VideoItem> out = [];
    for (final VideoItem v in src) {
      if (isBlocked(v.videoKey) || isHidden(v.videoKey)) continue;
      out.add(apply(v));
    }
    return out;
  }

  Future<void> load() async {
    try {
      final SharedPreferences prefs =
          await SharedPreferences.getInstance();
      blacklist =
          (prefs.getStringList('adm_blacklist') ?? []).toSet();
      try {
        final dynamic raw = jsonDecode(prefs.getString('adm_custom') ?? '{}');
        if (raw is Map) {
          custom = raw.map((k, val) => MapEntry(
              k.toString(),
              val is Map
                  ? Map<String, dynamic>.from(val)
                  : <String, dynamic>{}));
        }
      } catch (_) {}
      try {
        final dynamic s = jsonDecode(prefs.getString('adm_settings') ?? '{}');
        if (s is Map) _readSettings(s);
      } catch (_) {}
      localViews = prefs.getInt('adm_views') ?? 0;
    } catch (_) {}
    if (firebaseReady) {
      try {
        final FirebaseFirestore db = FirebaseFirestore.instance;
        final bl = await db
            .collection('blacklist_videos')
            .get()
            .timeout(const Duration(seconds: 10));
        blacklist = bl.docs.map((d) => d.id).toSet();
        final cv = await db
            .collection('custom_video_data')
            .get()
            .timeout(const Duration(seconds: 10));
        custom = {
          for (final d in cv.docs) d.id: Map<String, dynamic>.from(d.data())
        };
        final st = await db
            .collection('app_settings')
            .doc('main')
            .get()
            .timeout(const Duration(seconds: 10));
        if (st.exists && st.data() != null) _readSettings(st.data()!);
        final stats = await db
            .collection('app_stats')
            .doc('main')
            .get()
            .timeout(const Duration(seconds: 10));
        if (stats.exists && stats.data() != null) {
          fsUsers = (stats.data()!['users'] as int?) ?? 0;
          fsViews = (stats.data()!['views'] as int?) ?? 0;
        }
      } catch (_) {}
    }
  }

  void _readSettings(Map<dynamic, dynamic> s) {
    if (s['yandexEnabled'] is bool) {
      yandexEnabled = s['yandexEnabled'] as bool;
    }
    if (s['feedAdEvery'] is int && (s['feedAdEvery'] as int) > 0) {
      feedAdEvery = s['feedAdEvery'] as int;
    }
    if (s['reelsAdEvery'] is int && (s['reelsAdEvery'] as int) > 0) {
      reelsAdEvery = s['reelsAdEvery'] as int;
    }
    if (s['feedBlockId'] is String &&
        (s['feedBlockId'] as String).isNotEmpty) {
      feedBlockId = s['feedBlockId'] as String;
    }
    if (s['reelsBlockId'] is String &&
        (s['reelsBlockId'] as String).isNotEmpty) {
      reelsBlockId = s['reelsBlockId'] as String;
    }
    if (s['latestVersion'] is String) {
      latestVersion = s['latestVersion'] as String;
    }
    if (s['forceUpdate'] is bool) {
      forceUpdate = s['forceUpdate'] as bool;
    }
    if (s['adminPass'] is String &&
        (s['adminPass'] as String).length >= 4) {
      adminPass = s['adminPass'] as String;
    }
    if (s['customHtmlEnabled'] is bool) {
      customHtmlEnabled = s['customHtmlEnabled'] as bool;
    }
    if (s['customHtml'] is String) {
      customHtml = s['customHtml'] as String;
    }
    if (s['customHtmlPlacement'] is String) {
      final String p = s['customHtmlPlacement'] as String;
      customHtmlPlacement =
          p == 'feed' ? 'feed' : p == 'both' ? 'both' : 'player';
    }
    if (s['vkToken'] is String) {
      vkToken = s['vkToken'] as String;
    }
    if (s['videoSource'] is String) {
      final String m = s['videoSource'] as String;
      videoSource = m == 'parser' ? 'parser' : 'vkapi';
    }
    if (s['vkAppId'] is String) {
      vkAppId = s['vkAppId'] as String;
    }
    if (s['playerAdMode'] is String) {
      final String m = s['playerAdMode'] as String;
      playerAdMode =
          m == 'html' ? 'html' : m == 'yandex' ? 'yandex' : 'off';
    }
    if (s['playerAdEvery'] is int && (s['playerAdEvery'] as int) > 0) {
      playerAdEvery = s['playerAdEvery'] as int;
    }
    if (s['htmlPlayer'] is bool) htmlPlayer = s['htmlPlayer'] as bool;
    if (s['htmlOpen'] is bool) htmlOpen = s['htmlOpen'] as bool;
    if (s['htmlFeed'] is bool) htmlFeed = s['htmlFeed'] as bool;
    if (s['htmlReels'] is bool) htmlReels = s['htmlReels'] as bool;
  }

  Future<void> loadUserToken() async {
    try {
      final SharedPreferences prefs =
          await SharedPreferences.getInstance();
      userVkToken = prefs.getString('user_vk_token') ?? '';
      userVkId = prefs.getString('user_vk_id') ?? '';
    } catch (_) {}
  }

  Future<void> saveUserToken(String token, String uid) async {
    userVkToken = token;
    userVkId = uid;
    try {
      final SharedPreferences prefs =
          await SharedPreferences.getInstance();
      await prefs.setString('user_vk_token', token);
      await prefs.setString('user_vk_id', uid);
    } catch (_) {}
  }

  Future<void> clearUserToken() async {
    userVkToken = '';
    userVkId = '';
    try {
      final SharedPreferences prefs =
          await SharedPreferences.getInstance();
      await prefs.remove('user_vk_token');
      await prefs.remove('user_vk_id');
    } catch (_) {}
  }

  Map<String, dynamic> _settingsMap() => {
        'yandexEnabled': yandexEnabled,
        'feedAdEvery': feedAdEvery,
        'reelsAdEvery': reelsAdEvery,
        'feedBlockId': feedBlockId,
        'reelsBlockId': reelsBlockId,
        'latestVersion': latestVersion,
        'forceUpdate': forceUpdate,
        'adminPass': adminPass,
        'customHtmlEnabled': customHtmlEnabled,
        'customHtml': customHtml,
        'customHtmlPlacement': customHtmlPlacement,
        'vkToken': vkToken,
        'videoSource': videoSource,
        'playerAdMode': playerAdMode,
        'playerAdEvery': playerAdEvery,
        'htmlPlayer': htmlPlayer,
        'htmlOpen': htmlOpen,
        'htmlFeed': htmlFeed,
        'htmlReels': htmlReels,
      };

  Future<void> persist() async {
    try {
      final SharedPreferences prefs =
          await SharedPreferences.getInstance();
      await prefs.setStringList('adm_blacklist', blacklist.toList());
      await prefs.setString('adm_custom', jsonEncode(custom));
      await prefs.setString('adm_settings', jsonEncode(_settingsMap()));
      await prefs.setInt('adm_views', localViews);
    } catch (_) {}
    if (!firebaseReady) return;
    try {
      final FirebaseFirestore db = FirebaseFirestore.instance;
      await db
          .collection('app_settings')
          .doc('main')
          .set(_settingsMap(), SetOptions(merge: true))
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  Future<void> persistBlacklist(String key, bool blocked) async {
    await persist();
    if (!firebaseReady) return;
    try {
      final col = FirebaseFirestore.instance.collection('blacklist_videos');
      if (blocked) {
        await col
            .doc(key)
            .set({'createdAt': FieldValue.serverTimestamp()}).timeout(
                const Duration(seconds: 10));
      } else {
        await col.doc(key).delete().timeout(const Duration(seconds: 10));
      }
    } catch (_) {}
  }

  Future<void> persistCustom(String key) async {
    await persist();
    if (!firebaseReady) return;
    try {
      final col = FirebaseFirestore.instance.collection('custom_video_data');
      final Map<String, dynamic>? c = custom[key];
      if (c == null) {
        await col.doc(key).delete().timeout(const Duration(seconds: 10));
      } else {
        await col.doc(key).set(c, SetOptions(merge: true)).timeout(
            const Duration(seconds: 10));
      }
    } catch (_) {}
  }

  Future<void> loadRemote() async {
    try {
      final http.Response resp = await _getWithFallback(
          Uri.parse('$adminApiBase/api/admin/config'),
          const Duration(seconds: 5));
      if (resp.statusCode != 200) return;
      final dynamic data = jsonDecode(resp.body);
      if (data is! Map || data['success'] != true) return;
      final dynamic bl = data['blacklist'];
      if (bl is List) {
        blacklist.addAll(bl.map((e) => '$e'));
      }
      final dynamic cv = data['custom'];
      if (cv is Map) {
        cv.forEach((k, val) {
          if (val is Map) {
            custom['$k'] = Map<String, dynamic>.from(val);
          }
        });
      }
      final dynamic s = data['settings'];
      if (s is Map) {
        _readSettings(s);
        if (s['adminAppPass'] is String &&
            (s['adminAppPass'] as String).length >= 4) {
          adminPass = s['adminAppPass'] as String;
        }
      }
      await persist();
    } catch (_) {}
  }

  void postRemoteView() {
    try {
      http
          .post(Uri.parse('$adminApiBase/api/admin/stats/view'))
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
  }

  Future<void> bumpViews() async {
    localViews++;
    postRemoteView();
    try {
      final SharedPreferences prefs =
          await SharedPreferences.getInstance();
      await prefs.setInt('adm_views', localViews);
    } catch (_) {}
    if (!firebaseReady) return;
    try {
      await FirebaseFirestore.instance
          .collection('app_stats')
          .doc('main')
          .set({'views': FieldValue.increment(1)}, SetOptions(merge: true))
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
  }
}

class StreamApp extends StatelessWidget {
  const StreamApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TANHO',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(scaffoldBackgroundColor: bgColor, useMaterial3: true),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with WidgetsBindingObserver {
  int _selectedIndex = 0;
  int _currentShort = 0;
  String _searchQuery = '';
  final PageController _shortsPageController = PageController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  bool _searchFocused = false;
  final ScrollController _feedScrollController = ScrollController();
  bool _barsVisible = true;
  static const int _searchPageSize = 10;
  static const int _homePageSize = 50;
  int _searchOffset = 0;
  bool _searchHasMore = false;
  bool _searchPaged = false;
  bool _loadingMore = false;
  int _trendsOffset = 0;
  bool _trendsHasMore = true;
  bool _loadingHomeMore = false;
  Timer? _logoHoldTimer;
  bool _logoLongFired = false;
  final Map<int, InAppWebViewController> _webControllers = {};
  final Map<int, bool> _paused = {};
  final Map<int, bool> _webLoaded = {};
  final Map<int, int> _webCreatedAt = {};
  bool _inviteBannerDismissed = false;
  bool _isReelsLoading = false;

  List<VideoItem> _playlist = List.of(fallbackPlaylist);
  List<VideoItem> _shortsFeed = List.of(fallbackPlaylist);
  List<VideoItem> _searchResults = [];
  bool _isSearching = false;
  bool _isTrendsLoading = true;
  String? _vkError;
  bool _networkError = false;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _searchFocus.addListener(() {
      if (mounted) {
        setState(() {
          _searchFocused = _searchFocus.hasFocus;
        });
      }
    });
    _feedScrollController.addListener(_onFeedScrollNearEnd);
    adminStore.load().then((_) async {
      if (!mounted) return;
      await adminStore.loadUserToken();
      if (!mounted) return;
      final prefs = await SharedPreferences.getInstance();
      _inviteBannerDismissed = prefs.getBool('invite_banner_dismissed') ?? false;
      setState(() {});
      await adminStore.loadRemote();
      if (!mounted) return;
      _applyAdminToPlaylist();
      _checkForceUpdate();
      _maybeShowHtmlAd();
      _loadReels();
    });
    _loadTrends();
  }

  void _checkForceUpdate() {
    if (adminStore.latestVersion == appVersion) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (adminStore.forceUpdate) {
        _forceUpdateDialog();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Вышла версия ${adminStore.latestVersion}! Обновите приложение.'),
            backgroundColor: surfaceColor,
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: 'Обновить',
              textColor: secondaryPurple,
              onPressed: _openStoreListing,
            ),
          ),
        );
      }
    });
  }

  void _forceUpdateDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: const Color(0xFF161820),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text(
              'Доступно обновление',
              style: TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700),
            ),
            content: Text(
              'Ваша версия: $appVersion\nНовая версия: ${adminStore.latestVersion}\n\nБез обновления продолжение невозможно.',
              style:
                  const TextStyle(color: textSecondary, height: 1.5),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _openStoreListing();
                },
                child: const Text(
                  'Обновить в Play Store',
                  style: TextStyle(color: secondaryPurple),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _pauseWebVideo(_currentShort);
      if (mounted) {
        setState(() {
          _paused[_currentShort] = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _pauseWebVideo(_currentShort);
    WidgetsBinding.instance.removeObserver(this);
    _logoHoldTimer?.cancel();
    _searchDebounce?.cancel();
    _searchFocus.dispose();
    _searchController.dispose();
    _shortsPageController.dispose();
    _feedScrollController.dispose();
    super.dispose();
  }

  Future<void> _ensureNotificationPermission() async {
    try {
      final PermissionStatus st = await Permission.notification.status;
      if (!st.isGranted) {
        await Permission.notification.request();
      }
    } catch (_) {}
  }

  void _onFeedScrollNearEnd() {
    if (!_feedScrollController.hasClients) return;
    final double max =
        _feedScrollController.position.maxScrollExtent;
    final double cur = _feedScrollController.position.pixels;
    if (max - cur < 400) {
      if (_searchQuery.trim().isNotEmpty) {
        _loadMoreSearch();
      } else {
        _loadMoreHome();
      }
    }
  }

  Future<void> _loadMoreHome() async {
    if (_searchQuery.trim().isNotEmpty ||
        !_trendsHasMore ||
        _loadingHomeMore ||
        _isTrendsLoading) {
      return;
    }
    setState(() => _loadingHomeMore = true);
    try {
      final page = await _fetchCatalogPage(
          '', _trendsOffset, _homePageSize);
      if (!mounted) return;
      setState(() {
        for (final VideoItem v in page.videos) {
          if (!_playlist.contains(v)) {
            _playlist.add(v);
          }
        }
        _trendsOffset += page.videos.length;
        _trendsHasMore = _playlist.length < page.total &&
            page.videos.isNotEmpty;
        _loadingHomeMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingHomeMore = false);
    }
  }

  bool _onFeedScroll(UserScrollNotification n) {
    if (n.direction == ScrollDirection.reverse && _barsVisible) {
      _searchFocus.unfocus();
      setState(() => _barsVisible = false);
    } else if ((n.direction == ScrollDirection.forward ||
            n.direction == ScrollDirection.idle) &&
        !_barsVisible) {
      setState(() => _barsVisible = true);
    }
    return false;
  }



  void _resetHome() {
    _searchDebounce?.cancel();
    _searchController.clear();
    _resetSearchPaging();
    setState(() {
      _searchQuery = '';
      _searchResults = [];
      _isSearching = false;
      _vkError = null;
      _networkError = false;
      _selectedIndex = 0;
      _barsVisible = true;
    });
    _loadTrends();
  }

  String _friendlyVkError(Object e) {
    return 'Не удалось загрузить видео. Нажмите, чтобы повторить';
  }

  bool _isNetworkFailure(Object e) {
    final String s = '$e'.toLowerCase();
    return s.contains('socketexception') ||
        s.contains('failed host lookup') ||
        s.contains('network is unreachable') ||
        s.contains('connection refused') ||
        s.contains('connection reset') ||
        s.contains('connection timed out') ||
        s.contains('clientexception') ||
        s.contains('handshake');
  }

  Future<bool> _onBackPressed() async {
    if (_searchQuery.isNotEmpty) {
      _searchDebounce?.cancel();
      _searchController.clear();
      _resetSearchPaging();
      setState(() {
        _searchQuery = '';
        _searchResults = [];
        _isSearching = false;
        _vkError = null;
        _networkError = false;
      });
      return false;
    }
    if (_selectedIndex == 1 || _selectedIndex == 2) {
      await _pauseWebVideo(_currentShort);
      _searchDebounce?.cancel();
      _searchController.clear();
      _resetSearchPaging();
      setState(() {
        _selectedIndex = 0;
        _searchQuery = '';
        _searchResults = [];
        _isSearching = false;
        _vkError = null;
        _networkError = false;
        _barsVisible = true;
      });
      return false;
    }
    return true;
  }

  bool get _isPoliticalBlocked =>
      _searchQuery.trim().isNotEmpty &&
      isPoliticalContent(_searchQuery.trim());

  List<VideoItem> get _visibleHomeList {
    if (_searchQuery.trim().isEmpty) {
      return _playlist;
    }
    if (_isPoliticalBlocked) return const [];
    return _searchResults;
  }

  List<VideoItem> _verticalsOf(List<VideoItem> src) =>
      src.where((v) => v.vertical).toList();

  List<VideoItem> _horizontalsOf(List<VideoItem> src) =>
      src.where((v) => !v.vertical).toList();

  List<VideoItem> _reelsPool() {
    if (_reelsCatalog.isNotEmpty) return List.of(_reelsCatalog);
    final List<VideoItem> v = _verticalsOf(_playlist);
    return v.isNotEmpty ? v : List.of(_playlist);
  }

  VideoItem? _lastWatched;
  final Map<String, String> _directUrls = {};
  final Set<String> _directFetching = {};

  int _similarityScore(VideoItem a, VideoItem b) {
    if (a == b) return -1000;
    int s = 0;
    if (a.genre.isNotEmpty && a.genre == b.genre) s += 3;
    if (a.author.isNotEmpty && a.author == b.author) s += 1;
    final Set<String> aw =
        extractKeywords(a.title).map((e) => e.toLowerCase()).toSet();
    final Set<String> bw =
        extractKeywords(b.title).map((e) => e.toLowerCase()).toSet();
    s += aw.intersection(bw).length;
    return s;
  }

  List<VideoItem> _rankSimilar(List<VideoItem> pool, VideoItem? seed) {
    final List<VideoItem> list = List.of(pool);
    if (seed == null) {
      list.shuffle();
      return list;
    }
    final Map<VideoItem, int> order = {};
    for (int i = 0; i < list.length; i++) {
      order[list[i]] = i;
    }
    final Random rng = Random();
    list.sort((a, b) {
      final int d = _similarityScore(seed, b) - _similarityScore(seed, a);
      if (d != 0) return d;
      if (rng.nextBool()) return -1;
      return order[a]! - order[b]!;
    });
    return list;
  }

  VideoItem _catalogVideo(Map<String, dynamic> c) {
    final String key = '${c['key'] ?? ''}';
    final List<String> parts = key.split('_');
    final String oid = parts.isNotEmpty ? parts.first : '';
    final String vid = parts.length > 1 ? parts.sublist(1).join('_') : '';
    final String akey = '${c['akey'] ?? ''}';
    final String keyParams =
        akey.isNotEmpty ? '&hash=$akey&access_key=$akey' : '';
    final String title = '${c['title'] ?? 'Без названия'}';
    final int dur = c['durationSec'] is int
        ? c['durationSec'] as int
        : int.tryParse('${c['durationSec'] ?? 0}') ?? 0;
    final String durLabel = dur > 0 ? formatDuration(dur) : '';
    return VideoItem(
      title: title,
      author: 'VK Video',
      stats: durLabel.isNotEmpty ? durLabel : 'VK Video',
      views: 'VK Video',
      duration: durLabel,
      durationSec: dur,
      thumb: '${c['thumb'] ?? ''}',
      embedUrl: 'https://vk.com/video_ext.php?oid=$oid&id=$vid$keyParams',
      player: 'https://vk.com/video_ext.php?oid=$oid&id=$vid$keyParams',
      vertical: c['vertical'] == true,
      genre: '${c['genre'] ?? ''}',
      direct: c['direct'] == true,
    );
  }

  List<VideoItem> _mapCatalogItems(List<dynamic> items) {
    final Set<String> seenIds = {};
    final Set<String> seenTitles = {};
    final List<VideoItem> out = [];
    for (final dynamic raw in items) {
      if (raw is! Map<String, dynamic>) continue;
      final String key = '${raw['key'] ?? ''}';
      if (key.isEmpty || seenIds.contains(key)) continue;
      final String title = '${raw['title'] ?? ''}';
      final String tkey = '${title.toLowerCase().trim()}_${raw['durationSec']}';
      if (seenTitles.contains(tkey)) continue;
      if (isPoliticalContent(title)) continue;
      try {
        out.add(_catalogVideo(raw));
        seenIds.add(key);
        seenTitles.add(tkey);
      } catch (_) {}
    }
    return adminStore.filterFeed(out);
  }

  Future<List<VideoItem>> _fetchServerList(
      String path, Map<String, String> params) async {
    final Uri uri =
        Uri.parse('$adminApiBase$path').replace(queryParameters: params);
    final http.Response resp = await _getWithFallback(
        uri, const Duration(seconds: 5));
    if (resp.statusCode != 200) return const [];
    final dynamic data = jsonDecode(resp.body);
    final dynamic items = data is Map ? data['items'] : null;
    if (items is! List) return const [];
    return _mapCatalogItems(items);
  }

  Future<List<VideoItem>> _fetchTrends() {
    return _fetchServerList('/api/catalog/trends', {});
  }

  Future<List<VideoItem>> _fetchReelsFeed() {
    return _fetchServerList('/api/catalog/reels', {'limit': '200'});
  }

  Future<({List<VideoItem> videos, int total})> _fetchCatalogPage(
      String query, int offset, int limit) async {
    final Uri uri = Uri.parse('$adminApiBase/api/catalog').replace(
        queryParameters: {
          'q': query,
          'limit': '$limit',
          'offset': '$offset'
        });
    final http.Response resp = await _getWithFallback(
        uri, const Duration(seconds: 5));
    if (resp.statusCode != 200) {
      throw Exception('catalog HTTP ${resp.statusCode}');
    }
    final dynamic data = jsonDecode(resp.body);
    if (data is! Map) return (videos: const <VideoItem>[], total: 0);
    final dynamic items = data['items'];
    final int total = data['total'] is int
        ? data['total'] as int
        : (items is List ? items.length : 0);
    if (items is! List) return (videos: const <VideoItem>[], total: total);
    return (videos: _mapCatalogItems(items), total: total);
  }

  void _applyAdminToPlaylist() {
    setState(() {
      _playlist = adminStore.filterFeed(_playlist);
      _searchResults = adminStore.filterFeed(_searchResults);
      if (_shortsFeed.isEmpty && _playlist.isNotEmpty) {
        _shortsFeed = List.of(_playlist);
      }
    });
  }

  Future<List<String>> _getInterests() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(interestsPrefsKey) ?? [];
    } catch (_) {
      return [];
    }
  }

  Future<void> _pushInterests(List<String> keywords) async {
    final List<String> clean = keywords
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.length >= 3)
        .toList();
    if (clean.isEmpty) return;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final List<String> cur =
          prefs.getStringList(interestsPrefsKey) ?? [];
      for (final String k in clean) {
        cur.removeWhere((e) => e == k);
        cur.insert(0, k);
      }
      await prefs.setStringList(
          interestsPrefsKey, cur.take(maxInterests).toList());
    } catch (_) {}
  }

  void _rememberVideoTopics(VideoItem v) {
    _pushInterests(extractKeywords(v.title));
  }

  List<VideoItem> _reelsCatalog = [];

  Future<void> _loadTrends() async {
    setState(() {
      _isTrendsLoading = true;
      _vkError = null;
      _networkError = false;
      _trendsOffset = 0;
      _trendsHasMore = true;
      _loadingHomeMore = false;
    });
    try {
      List<VideoItem> fresh = [];
      int total = 0;
      try {
        final page = await _fetchCatalogPage(
                '', 0, _homePageSize)
            .timeout(const Duration(seconds: 12));
        fresh = page.videos;
        total = page.total;
      } catch (_) {
        fresh = [];
      }
      if (fresh.isEmpty) {
        try {
          fresh = await _fetchTrends()
              .timeout(const Duration(seconds: 8));
          total = fresh.length;
        } catch (_) {
          fresh = [];
        }
      }
      if (!mounted) return;
      if (fresh.isEmpty) throw Exception('empty feed');
      try {
        final List<String> interests = await _getInterests()
            .timeout(const Duration(seconds: 2));
        if (interests.isNotEmpty) {
          final Set<String> words = interests
              .expand((e) => e.split(RegExp(r'\s+')))
              .map((e) => e.toLowerCase())
              .where((e) => e.length > 2)
              .toSet();
          int score(VideoItem v) {
            final String t = '${v.title} ${v.genre}'.toLowerCase();
            int s = 0;
            for (final String w in words) {
              if (t.contains(w)) s++;
            }
            return s;
          }

          fresh.sort((a, b) => score(b).compareTo(score(a)));
        } else {
          // No user interests — shuffle for variety on each launch
          fresh.shuffle();
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        final List<VideoItem> keep =
            _playlist.where((v) => !fresh.contains(v)).toList();
        _playlist = [...fresh, ...keep];
        _trendsOffset = fresh.length;
        _trendsHasMore =
            total > 0 && fresh.length < total && fresh.isNotEmpty;
        if (_shortsFeed.length == fallbackPlaylist.length) {
          _shortsFeed = _reelsPool();
        }
        _isTrendsLoading = false;
      });
      _maybeShowHtmlAd();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (_playlist.isEmpty) {
          _networkError = _isNetworkFailure(e);
          _vkError = _networkError ? 'network' : _friendlyVkError(e);
        }
        _isTrendsLoading = false;
      });
    }
  }

  Future<void> _loadReels() async {
    setState(() => _isReelsLoading = true);
    try {
      final List<VideoItem> reels = await _fetchReelsFeed()
          .timeout(const Duration(seconds: 8));
      if (!mounted) return;
      setState(() {
        _reelsCatalog = reels;
        _isReelsLoading = false;
        if (_selectedIndex == 1 && _shortsFeed.isEmpty) {
          _shortsFeed = _reelsPool();
          _currentShort = 0;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _isReelsLoading = false);
    }
  }

  void _saveWatched(VideoItem v) {
    _rememberVideoTopics(v);
    _saveHistory(v);
    _lastWatched = v;
    adminStore.bumpViews();
    if (!_playlist.contains(v)) {
      setState(() {
        _playlist.add(v);
      });
    }
  }

  static const String historyPrefsKey = 'watch_history_v1';
  static const int maxHistory = 30;

  Future<void> _saveHistory(VideoItem v) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final List<String> cur =
          prefs.getStringList(historyPrefsKey) ?? [];
      final List<Map<String, dynamic>> items = [];
      for (final String raw in cur) {
        try {
          final dynamic d = jsonDecode(raw);
          if (d is Map<String, dynamic> &&
              d['embedUrl'] is String &&
              d['embedUrl'] != v.embedUrl) {
            items.add(d);
          }
        } catch (_) {}
      }
      items.insert(0, {
        'title': v.title,
        'thumb': v.thumb,
        'embedUrl': v.embedUrl,
        'views': v.views,
        'player': v.player,
        'duration': v.duration,
        'durationSec': v.durationSec,
        'genre': v.genre,
        'direct': v.direct,
      });
      await prefs.setStringList(historyPrefsKey,
          items.take(maxHistory).map(jsonEncode).toList());
    } catch (_) {}
  }

  void _onSearchChanged(String v) {
    _searchDebounce?.cancel();
    setState(() {
      _searchQuery = v;
      final String t = v.trim();
      if (t.isEmpty) {
        _searchResults = [];
        _isSearching = false;
        _vkError = null;
        _networkError = false;
      } else {
        // Reset search state
      }
    });
    final String q = v.trim();
    if (q.isEmpty || isPoliticalContent(q)) return;
    if (q.length < 2) return;
    _searchDebounce = Timer(const Duration(milliseconds: 600), () {
      _searchVk(q);
    });
  }

  void _resetSearchPaging() {
    _searchOffset = 0;
    _searchHasMore = false;
    _searchPaged = false;
    _loadingMore = false;
  }

  Future<void> _searchVk(String query) async {
    if (isPoliticalContent(query)) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }
    setState(() {
      _isSearching = true;
      _vkError = null;
      _networkError = false;
      _resetSearchPaging();
    });
    try {
      final page =
          await _fetchCatalogPage(query, 0, _searchPageSize);
      if (!mounted) return;
      if (_searchQuery.trim() != query) return;
      _pushInterests([query]);
      setState(() {
        _searchResults = page.videos;
        _searchOffset = page.videos.length;
        _searchHasMore =
            page.videos.length < page.total;
        _searchPaged = true;
        _isSearching = false;
        _vkError = null;
        _networkError = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _networkError = _isNetworkFailure(e);
        _vkError = _networkError ? 'network' : _friendlyVkError(e);
        _isSearching = false;
      });
    }
  }

  Future<({List<VideoItem> videos, int total})> _fetchFeedPage(
      String mode, int offset) async {
    final Uri uri = Uri.parse('$adminApiBase/api/catalog').replace(
        queryParameters: {
          'sort': mode == 'popular' ? 'popular' : 'new',
          'limit': '$_searchPageSize',
          'offset': '$offset'
        });
    final http.Response resp = await _getWithFallback(
        uri, const Duration(seconds: 5));
    if (resp.statusCode != 200) {
      throw Exception('catalog HTTP ${resp.statusCode}');
    }
    final dynamic data = jsonDecode(resp.body);
    if (data is! Map) return (videos: const <VideoItem>[], total: 0);
    final dynamic items = data['items'];
    final int total = data['total'] is int
        ? data['total'] as int
        : (items is List ? items.length : 0);
    if (items is! List) return (videos: const <VideoItem>[], total: total);
    return (videos: _mapCatalogItems(items), total: total);
  }

  Future<void> _loadMoreSearch() async {
    final String query = _searchQuery.trim();
    if (query.isEmpty ||
        !_searchPaged ||
        !_searchHasMore ||
        _loadingMore ||
        _isSearching) {
      return;
    }
    setState(() => _loadingMore = true);
    try {
      final page = await _fetchCatalogPage(
          query, _searchOffset, _searchPageSize);
      if (!mounted) return;
      if (_searchQuery.trim() != query) return;
      setState(() {
        for (final VideoItem v in page.videos) {
          if (!_searchResults.contains(v)) {
            _searchResults.add(v);
          }
        }
        _searchOffset += page.videos.length;
        _searchHasMore =
            _searchResults.length < page.total &&
                page.videos.isNotEmpty;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  void _openShortsFromList(List<VideoItem> list, int index) {
    if (list.isEmpty) return;
    final int safe = index.clamp(0, list.length - 1);
    final VideoItem v = list[safe];
    _saveWatched(v);
    _ensureNotificationPermission();
    _resolveDirect(v);
    List<VideoItem> pool =
        v.vertical ? _reelsPool() : _horizontalsOf(_playlist);
    int vi = pool.indexWhere((e) => e == v);
    if (vi < 0) {
      pool = [v];
      vi = 0;
    }
    final int videoIdx = vi;
    final int tapMs = DateTime.now().millisecondsSinceEpoch;
    setState(() {
      _shortsFeed = List.of(pool);
      _selectedIndex = 1;
      final int pos = _shortsAdsOn()
          ? videoIdx + (videoIdx ~/ adminStore.reelsAdEvery)
          : videoIdx;
      _currentShort = pos;
      _paused[pos] = false;
      _webLoaded.clear();
      _webCreatedAt.clear();
      _webCreatedAt[pos] = tapMs;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_shortsPageController.hasClients) {
        _shortsPageController.jumpToPage(_currentShort);
      }
    });
  }

  Future<void> _pauseWebVideo(int index) async {
    try {
      await _webControllers[index]?.evaluateJavascript(source: 'vkPause();');
    } catch (_) {}
  }

  Future<void> _playWebVideo(int index) async {
    try {
      await _webControllers[index]?.evaluateJavascript(source: 'vkPlay();');
    } catch (_) {}
  }

  Future<void> _resolveDirect(VideoItem v) async {
    if (!v.direct) return;
    if (_directUrls.containsKey(v.embedUrl) ||
        _directFetching.contains(v.embedUrl)) {
      return;
    }
    _directFetching.add(v.embedUrl);
    try {
      final Uri uri = Uri.parse('$adminApiBase/api/stream-vk').replace(
          queryParameters: {'oid': v.vkOid, 'id': v.vkId});
      final http.Response resp =
          await _getWithFallback(uri, const Duration(seconds: 5));
      if (!mounted) return;
      final dynamic data = jsonDecode(resp.body);
      final dynamic u =
          data is Map ? data['url'] : null;
      if (u is String && u.startsWith('http')) {
        _directUrls[v.embedUrl] = u;
        if (mounted) setState(() {});
      }
    } catch (_) {
    } finally {
      _directFetching.remove(v.embedUrl);
    }
  }

  void _skipBrokenShort() {
    if (!mounted || _selectedIndex != 1) return;
    if (_shortsPageController.hasClients &&
        _currentShort + 1 < _shortsItemCount()) {
      _shortsPageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _togglePause(int index) {
    final bool paused = _paused[index] ?? false;
    if (paused) {
      setState(() {
        _paused[index] = false;
      });
      _playWebVideo(index);
    } else {
      setState(() {
        _paused[index] = true;
      });
      _pauseWebVideo(index);
    }
  }

  bool _shortsAdsOn() =>
      adminStore.yandexEnabled &&
      adminStore.reelsBlockId.isNotEmpty &&
      adminStore.reelsAdEvery > 0;

  bool _shortsHtmlOn() =>
      _htmlInReels() && adminStore.reelsAdEvery > 0;

  bool _shortsSlotsOn() => _shortsAdsOn() || _shortsHtmlOn();

  int _shortsStep() => adminStore.reelsAdEvery + 1;

  bool _isAdPos(int pos) =>
      _shortsSlotsOn() && (pos + 1) % _shortsStep() == 0;

  int _shortsPosToVideo(int pos) =>
      _shortsSlotsOn() ? pos - (pos ~/ _shortsStep()) : pos;

  int _shortsItemCount() => _shortsSlotsOn()
      ? _shortsFeed.length +
          (_shortsFeed.length ~/ adminStore.reelsAdEvery)
      : _shortsFeed.length;

  void _onShortsPageChanged(int pos) {
    final int prev = _currentShort;
    int playPos = -1;
    if (!_isAdPos(pos)) {
      final int vi = _shortsPosToVideo(pos);
      if (vi >= 0 && vi < _shortsFeed.length) {
        _saveWatched(_shortsFeed[vi]);
        _resolveDirect(_shortsFeed[vi]);
        playPos = pos;
      }
    }
    setState(() {
      _currentShort = pos;
      _paused[prev] = false;
      _paused[pos] = false;
    });
    _pauseWebVideo(prev);
    if (playPos >= 0) _playWebVideo(playPos);
  }

  @override
  Widget build(BuildContext context) {
    final double navPad = MediaQuery.of(context).padding.bottom;
    final bool canClose =
        _searchQuery.isEmpty && _selectedIndex == 0;
    return PopScope(
      canPop: canClose,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        final bool close = await _onBackPressed();
        if (close && context.mounted) {
          Navigator.of(context).maybePop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: appBgGradient,
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(child: _buildScreen()),
              if (_selectedIndex != 1)
                Positioned(
                  bottom: 8 + navPad,
                  left: 16,
                  right: 16,
                  height: 58,
                  child: AnimatedSlide(
                    offset: _barsVisible
                        ? Offset.zero
                        : const Offset(0, 1),
                    duration:
                        const Duration(milliseconds: 400),
                    curve: Curves.easeInOutCubic,
                    child: _buildGlassCapsule(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScreen() {
    switch (_selectedIndex) {
      case 0:
        return _homeScreen();
      case 1:
        return _shortsScreen();
      case 2:
        return _catalogScreen();
      default:
        return _homeScreen();
    }
  }

  Widget _buildGlassCapsule() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 58,
          decoration: BoxDecoration(
            color: const Color(0xFF161820).withOpacity(0.75),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _capsuleItem(Icons.home_rounded, 0),
              _capsuleItem(Icons.movie_creation_outlined, 1),
              _capsuleItem(Icons.grid_view_rounded, 2),
            ],
          ),
        ),
      ),
    );
  }

  Widget _capsuleItem(IconData icon, int index) {
    final bool active = _selectedIndex == index;
    return GestureDetector(
      onTap: () {
        if (_selectedIndex == 1 && index != 1) {
          _pauseWebVideo(_currentShort);
        }
        if (index == 0) {
          _resetHome();
          return;
        }
        final bool rebuildReels =
            index == 1 && _selectedIndex != 1;
        setState(() {
          _barsVisible = true;
          if (rebuildReels) {
            _shortsFeed = _rankSimilar(_reelsPool(), _lastWatched);
            _currentShort = 0;
            _webLoaded.clear();
            _webCreatedAt.clear();
          }
          _selectedIndex = index;
        });
        // Ensure reels loads if not yet loaded
        if (rebuildReels && _reelsCatalog.isEmpty && !_isReelsLoading) {
          _loadReels();
        }
        if (rebuildReels) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_shortsPageController.hasClients) {
              _shortsPageController.jumpToPage(0);
            }
          });
        }
      },
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? Colors.white.withOpacity(0.12) : Colors.transparent,
          boxShadow: active
              ? [
                  BoxShadow(
                    color: secondaryPurple.withOpacity(0.6),
                    blurRadius: 12,
                  ),
                ]
              : null,
        ),
        child: AnimatedScale(
          scale: active ? 1.15 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: Icon(
            icon,
            color: active ? Colors.white : navIconIdle,
            size: 24,
          ),
        ),
      ),
    );
  }


  Widget _buildInviteBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [primaryPurple, secondaryPurple],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Пригласи друга',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Поделись приложением — друзья скачают из Play Market',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white70,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: [
              ElevatedButton(
                onPressed: _shareApp,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: primaryPurple,
                ),
                child: const Text('Отправить ссылку'),
              ),
              TextButton(
                onPressed: _dismissInviteBanner,
                child: const Text(
                  'Закрыть',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _dismissInviteBanner() async {
    try {
      final SharedPreferences prefs =
          await SharedPreferences.getInstance();
      await prefs.setBool('invite_banner_dismissed', true);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _inviteBannerDismissed = true);
  }

  Future<void> _openStoreListing() async {
    try {
      final Uri market =
          Uri.parse('market://details?id=su.layn.app');
      if (await canLaunchUrl(market)) {
        await launchUrl(market);
        return;
      }
    } catch (_) {}
    await _openLink(storeUrl);
  }

  Future<void> _rateApp() => _openStoreListing();

  void _shareApp() {
    try {
      Share.share(
          'Смотри TANHO — видео без политики: https://play.google.com/store/apps/details?id=su.layn.app');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Ссылка: https://play.google.com/store/apps/details?id=su.layn.app'),
          backgroundColor: surfaceColor,
        ),
      );
    }
  }

  Future<void> _openLink(String url) async {
    try {
      final Uri uri = Uri.parse(url);
      final bool ok = await launchUrl(uri,
          mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(url),
            backgroundColor: surfaceColor,
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(url),
          backgroundColor: surfaceColor,
        ),
      );
    }
  }

  bool _htmlReady() {
    return adminStore.customHtml.trim().isNotEmpty;
  }

  bool _htmlInPlayer() {
    return _htmlReady() && adminStore.htmlPlayer;
  }

  bool _htmlInFeed() {
    return _htmlReady() && adminStore.htmlFeed;
  }

  bool _htmlInReels() {
    return _htmlReady() && adminStore.htmlReels;
  }

  bool _htmlOnOpen() {
    return _htmlReady() && adminStore.htmlOpen;
  }

  void _maybeShowHtmlAd() {
    if (!_htmlOnOpen()) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 1500));
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const CustomHtmlAdScreen(),
        ),
      );
    });
  }

  Widget _homeScreen() {
    return SafeArea(
      top: true,
      bottom: false,
      child: Column(
        children: [
          ClipRect(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOutCubic,
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: _barsVisible ? double.infinity : 0,
                ),
                child: AnimatedSlide(
                  offset: _barsVisible
                      ? Offset.zero
                      : const Offset(0, -1),
                  duration:
                      const Duration(milliseconds: 400),
                  curve: Curves.easeInOutCubic,
                  child: _homeHeader(),
                ),
              ),
            ),
          ),
          Expanded(child: _homeFeed()),
        ],
      ),
    );
  }

  Widget _homeHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              if (_logoLongFired) {
                _logoLongFired = false;
                return;
              }
              _resetHome();
            },
            onTapDown: (_) {
              _logoHoldTimer?.cancel();
              _logoHoldTimer =
                  Timer(const Duration(seconds: 3), () {
                _logoLongFired = true;
                _openAdminLogin();
              });
            },
            onTapUp: (_) => _logoHoldTimer?.cancel(),
            onTapCancel: () => _logoHoldTimer?.cancel(),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [primaryPurple, secondaryPurple],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(50),
                    boxShadow: [
                      BoxShadow(
                        color: secondaryPurple.withOpacity(0.7),
                        blurRadius: 16,
                        spreadRadius: 1,
                        offset: const Offset(0, 0),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text(
                      'T',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                              color: secondaryPurple,
                              blurRadius: 8,
                            ),
                          ]),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'TANHO',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 1.2),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                border: Border.all(
                    color: _searchFocused
                        ? secondaryPurple
                        : Colors.white.withOpacity(0.16),
                    width: _searchFocused ? 2 : 1.5),
                borderRadius: BorderRadius.circular(24),
                boxShadow: _searchFocused
                    ? [
                        BoxShadow(
                          color: secondaryPurple.withOpacity(0.45),
                          blurRadius: 14,
                        ),
                      ]
                    : null,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocus,
                      onChanged: _onSearchChanged,
                      onSubmitted: (v) {
                        final String q = v.trim();
                        if (q.isNotEmpty && !isPoliticalContent(q)) {
                          _searchDebounce?.cancel();
                          _searchVk(q);
                        }
                      },
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600),
                      decoration: const InputDecoration(
                        hintText: 'Поиск видео...',
                        hintStyle: TextStyle(
                            color: navIconIdle,
                            fontSize: 14,
                            fontWeight: FontWeight.w500),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'Голосовой поиск появится в следующем обновлении'),
                          backgroundColor: surfaceColor,
                        ),
                      );
                    },
                    child: const Icon(Icons.mic_rounded,
                        color: secondaryPurple, size: 20),
                  ),
                  const SizedBox(width: 10),
                  _isSearching
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: secondaryPurple,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.search_rounded,
                          color: secondaryPurple, size: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _homeFeed() {
    if (_isPoliticalBlocked) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(50),
                  border: Border.all(color: Colors.red.withOpacity(0.4)),
                ),
                child: const Icon(Icons.block_rounded,
                    color: Colors.red, size: 32),
              ),
              const SizedBox(height: 16),
              const Text(
                'Политический контент запрещен в приложении',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                    height: 1.4),
              ),
              const SizedBox(height: 8),
              const Text(
                'Попробуйте другой запрос',
                style: TextStyle(fontSize: 13, color: textMuted),
              ),
            ],
          ),
        ),
      );
    }
    if (_searchQuery.trim().isNotEmpty && _isSearching) {
      return const Center(
        child: CircularProgressIndicator(color: secondaryPurple),
      );
    }
    final List<VideoItem> items = _visibleHomeList;
    if (_isTrendsLoading && items.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: secondaryPurple),
            SizedBox(height: 12),
            Text('Загрузка...',
                style: TextStyle(color: textMuted, fontSize: 13)),
          ],
        ),
      );
    }
    if ((_networkError || _vkError != null) && items.isEmpty) {
      final bool searching = _searchQuery.trim().isNotEmpty;
      final String message = _networkError
          ? 'Проверьте подключение к интернету'
          : _vkError ?? 'Не удалось загрузить видео';
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: secondaryPurple.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(50),
                  border: Border.all(
                      color: secondaryPurple.withOpacity(0.4)),
                ),
                child: Icon(
                    _networkError
                        ? Icons.wifi_off_rounded
                        : Icons.refresh_rounded,
                    color: secondaryPurple,
                    size: 32),
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                    height: 1.4),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () {
                  if (searching) {
                    _searchVk(_searchQuery.trim());
                  } else {
                    _loadTrends();
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 28, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [primaryPurple, secondaryPurple],
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Text(
                    'Повторить',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (items.isEmpty) {
      return const Center(
        child: Text(
          'Ничего не найдено',
          style: TextStyle(color: textMuted, fontSize: 14),
        ),
      );
    }
    final bool adsOn = adminStore.yandexEnabled &&
        adminStore.feedBlockId.isNotEmpty &&
        adminStore.feedAdEvery > 0;
    final bool slots = (adsOn || _htmlInFeed()) &&
        adminStore.feedAdEvery > 0;
    final int step = adminStore.feedAdEvery + 1;
    final int adCount =
        slots ? items.length ~/ adminStore.feedAdEvery : 0;
    final int adWidth =
        (MediaQuery.of(context).size.width - 32).round();
    final bool searching = _searchQuery.trim().isNotEmpty;
    final bool showLoader =
        (searching && _searchPaged && _loadingMore) ||
            (!searching && _trendsHasMore && _loadingHomeMore);
    final int totalCount =
        items.length + adCount + (showLoader ? 1 : 0);
    return NotificationListener<UserScrollNotification>(
      onNotification: _onFeedScroll,
      child: RefreshIndicator(
        color: secondaryPurple,
        backgroundColor: surfaceColor,
        onRefresh: _loadTrends,
        child: ListView.builder(
          controller: _feedScrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
          itemCount: totalCount,
          itemBuilder: (ctx, i) {
            if (showLoader && i == totalCount - 1) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      color: secondaryPurple,
                      strokeWidth: 3,
                    ),
                  ),
                ),
              );
            }
            if (slots && (i + 1) % step == 0) {
              if (_htmlInFeed()) {
                return HtmlFeedCard(
                  key: ValueKey('htmlad_$i'),
                  maxWidth: adWidth,
                );
              }
              if (adsOn) {
                return YandexFeedAd(
                  key: ValueKey('yandex_$i'),
                  blockId: adminStore.feedBlockId,
                  maxWidth: adWidth,
                );
              }
            }
            final int vi = slots ? i - (i ~/ step) : i;
            final VideoItem v = items[vi];
            return _feedCard(v, items, vi);
          },
        ),
      ),
    );
  }

  Widget _feedCard(VideoItem v, List<VideoItem> list, int index) {
    return GestureDetector(
      onTap: () => _openShortsFromList(list, index),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                decoration: BoxDecoration(
                  color: surfaceColor,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        thumbProxy(v.thumb),
                        fit: BoxFit.cover,
                        loadingBuilder: (ctx, child, progress) {
                          if (progress == null) {
                            return child;
                          }
                          return Container(
                            color: placeholderPurple,
                            child: const Center(
                              child: SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(
                                  color: secondaryPurple,
                                  strokeWidth: 3,
                                ),
                              ),
                            ),
                          );
                        },
                        errorBuilder: (ctx, err, stack) {
                          return Container(
                            color: placeholderPurple,
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.play_circle_fill,
                                    color: secondaryPurple,
                                    size: 48,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'VK Video',
                                    style: TextStyle(
                                      color: secondaryPurple.withOpacity(0.8),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Нажми, чтобы запустить',
                                    style: TextStyle(
                                      color: secondaryPurple.withOpacity(0.6),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      Positioned(
                        bottom: 12,
                        left: 12,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(50),
                          ),
                          child: const Icon(Icons.play_arrow_rounded,
                              color: Colors.white, size: 18),
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: GestureDetector(
                          onTap: () => _reportVideoDialog(v),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color:
                                  Colors.black.withOpacity(0.5),
                              borderRadius:
                                  BorderRadius.circular(50),
                            ),
                            child: const Icon(
                                Icons.flag_rounded,
                                color: Colors.white,
                                size: 16),
                          ),
                        ),
                      ),
                      if (v.duration.isNotEmpty)
                        Positioned(
                          bottom: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.75),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              v.duration,
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              v.title,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                  height: 1.3),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.visibility_rounded,
                    size: 13, color: textMuted),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '${v.views} • VK Video',
                    style: const TextStyle(
                        fontSize: 13, color: textMuted),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _reportVideoDialog(VideoItem v) {
    const List<String> reasons = [
      'Спам',
      'Неподобающий контент',
      'Нарушение авторских прав',
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161820),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Пожаловаться на видео',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white),
                ),
                const SizedBox(height: 12),
                for (final String r in reasons)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.flag_outlined,
                        color: Colors.orange),
                    title: Text(r,
                        style:
                            const TextStyle(color: Colors.white)),
                    onTap: () {
                      Navigator.pop(ctx);
                      final Uri mail = Uri(
                        scheme: 'mailto',
                        path: 'ceonoyob@gmail.com',
                        queryParameters: {
                          'subject': 'Жалоба на видео: $r',
                          'body':
                              'Видео: ${v.title}\nСсылка: ${v.embedUrl}',
                        },
                      );
                      _openLink(mail.toString());
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _playerAdEveryOk(int index) {
    final int every =
        adminStore.playerAdEvery > 0 ? adminStore.playerAdEvery : 4;
    final int vi = _shortsPosToVideo(index);
    return vi > 0 && vi % every == 0;
  }

  bool _showHtmlPlayerAd(int index) {
    if (_paused[index] ?? false) return false;
    if (!_htmlInPlayer()) return false;
    return _playerAdEveryOk(index);
  }

  bool _showYandexPlayerAd(int index) {
    if (_paused[index] ?? false) return false;
    if (adminStore.playerAdMode != 'yandex') return false;
    if (!_playerAdEveryOk(index)) return false;
    if (!adminStore.yandexEnabled ||
        adminStore.reelsBlockId.isEmpty) {
      return false;
    }
    return _showHtmlPlayerAd(index) ? false : true;
  }

  Widget _playerAdOverlay(int index, String mode) {
    final double w = MediaQuery.of(context).size.width;
    final double reelsPad = MediaQuery.of(context).padding.bottom;
    return Positioned(
      bottom: 150 + reelsPad,
      left: 12,
      right: 12,
      child: PlayerAdBanner(
        key: ValueKey('playerad_${mode}_$index'),
        mode: mode,
        html: adminStore.customHtml,
        blockId: adminStore.reelsBlockId,
        maxWidth: (w - 24).round(),
      ),
    );
  }

  Widget _shortsScreen() {
    if (_shortsFeed.isEmpty) {
      if (_isReelsLoading) {
        return Container(
          color: Colors.black,
          child: const Center(
            child: CircularProgressIndicator(color: secondaryPurple),
          ),
        );
      }
      return Container(
        color: Colors.black,
        child: const Center(
          child: Text('Нет видео',
              style: TextStyle(color: Colors.white, fontSize: 14)),
        ),
      );
    }
    return Stack(
      children: [
        PageView.builder(
          controller: _shortsPageController,
          scrollDirection: Axis.vertical,
          itemCount: _shortsItemCount(),
          onPageChanged: _onShortsPageChanged,
          itemBuilder: (ctx, i) {
            if (_isAdPos(i)) {
              return _htmlInReels()
                  ? _shortsHtmlCard(i)
                  : _shortsAdCard(i);
            }
            return _shortItem(_shortsFeed[_shortsPosToVideo(i)], i);
          },
        ),
        SafeArea(
          top: true,
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () {
                    _pauseWebVideo(_currentShort);
                    setState(() {
                      _selectedIndex = 0;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    child: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white, size: 24),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _shortsHtmlCard(int pos) {
    return HtmlReelsCard(
      key: ValueKey('htmlreels_$pos'),
    );
  }

  Widget _shortsAdCard(int pos) {
    final double w = MediaQuery.of(context).size.width;
    return Container(
      color: Colors.black,
      child: SafeArea(
        top: true,
        bottom: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(
                child: Text(
                  'Реклама • Яндекс',
                  style: TextStyle(fontSize: 12, color: textMuted),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 420,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: YandexFeedAd(
                    key: ValueKey('yandex_reels_$pos'),
                    blockId: adminStore.reelsBlockId,
                    maxWidth: (w - 32).round(),
                    height: 420,
                    showLabel: false,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Center(
                child: Text(
                  'Свайпните вверх, чтобы продолжить',
                  style: TextStyle(
                      fontSize: 13,
                      color: textSecondary,
                      fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _shortItem(VideoItem v, int index) {
    final bool paused = _paused[index] ?? false;
    final double tapSide = MediaQuery.of(context).size.width;
    final double reelsPad = MediaQuery.of(context).padding.bottom;
    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          if (!(_webLoaded[index] ?? false))
            Positioned.fill(
              child: Image.network(
                thumbProxy(v.thumb),
                fit: BoxFit.cover,
                errorBuilder: (ctx, err, stack) =>
                    Container(color: Colors.black),
              ),
            ),
          Positioned.fill(
            child: SafeArea(
              top: false,
              left: false,
              right: false,
              bottom: true,
              child: Padding(
                padding: EdgeInsets.only(
                    bottom:
                        MediaQuery.of(context).padding.bottom > 0 ? 8 : 0),
                child: InAppWebView(
                  initialData: InAppWebViewInitialData(
                    data: _directUrls[v.embedUrl] != null
                        ? vkDirectHtml(
                            _directUrls[v.embedUrl]!,
                            index == _currentShort && !paused)
                        : vkPlayerHtml(
                            v, index == _currentShort && !paused),
                  ),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                domStorageEnabled: true,
                thirdPartyCookiesEnabled: true,
                iframeAllowFullscreen: true,
                mediaPlaybackRequiresUserGesture: false,
                allowsInlineMediaPlayback: true,
                allowBackgroundAudioPlaying: false,
                userAgent:
                    'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36',
              ),
              onWebViewCreated: (controller) {
                _webControllers[index] = controller;
                _webCreatedAt[index] =
                    DateTime.now().millisecondsSinceEpoch;
              },
              onConsoleMessage: (controller, consoleMessage) {
                if (consoleMessage.message
                    .toString()
                    .contains('VK_PLAYER_ERROR')) {
                  _skipBrokenShort();
                }
              },
              shouldOverrideUrlLoading:
                  (controller, navigationAction) async {
                final Uri? uri = navigationAction.request.url;
                if (uri == null) {
                  return NavigationActionPolicy.CANCEL;
                }
                if (uri.scheme == 'data' ||
                    uri.scheme == 'about' ||
                    uri.scheme == 'blob') {
                  return NavigationActionPolicy.ALLOW;
                }
                if (uri.toString().contains('video_ext.php')) {
                  return NavigationActionPolicy.ALLOW;
                }
                return NavigationActionPolicy.CANCEL;
              },
              onCreateWindow: (controller, createWindowAction) async {
                return false;
              },
              onEnterFullscreen: (controller) async {
                await SystemChrome.setPreferredOrientations([
                  DeviceOrientation.landscapeLeft,
                  DeviceOrientation.landscapeRight,
                ]);
                await SystemChrome.setEnabledSystemUIMode(
                    SystemUiMode.immersiveSticky);
              },
              onExitFullscreen: (controller) async {
                await SystemChrome.setPreferredOrientations([
                  DeviceOrientation.portraitUp,
                ]);
                await SystemChrome.setEnabledSystemUIMode(
                    SystemUiMode.edgeToEdge);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    setState(() {
                      _barsVisible = true;
                    });
                  }
                });
              },
              onLoadStop: (controller, uri) async {
                if (index != _currentShort || (_paused[index] ?? false)) {
                  return;
                }
                final int createdAt = _webCreatedAt[index] ?? 0;
                if (createdAt > 0) {
                  debugPrint(
                      'webview[$index] page ms=${DateTime.now().millisecondsSinceEpoch - createdAt}');
                }
                _webLoaded[index] = true;
                if (mounted) setState(() {});
                for (int attempt = 0; attempt < 3; attempt++) {
                  await Future.delayed(Duration(
                      milliseconds: attempt == 0
                          ? 300
                          : attempt == 1
                              ? 800
                              : 1500));
                  if (!mounted ||
                      index != _currentShort ||
                      (_paused[index] ?? false)) {
                    return;
                  }
                  await _playWebVideo(index);
                }
              },
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Center(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => _togglePause(index),
                child: SizedBox(
                  width: tapSide,
                  height: tapSide,
                  child: Container(color: Colors.transparent),
                ),
              ),
            ),
          ),
          if (_showHtmlPlayerAd(index))
            _playerAdOverlay(index, 'html'),
          if (_showYandexPlayerAd(index))
            _playerAdOverlay(index, 'yandex'),
          if (paused)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => _togglePause(index),
                child: Container(
                  color: Colors.black.withOpacity(0.92),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(50),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.8),
                                width: 2),
                          ),
                          child: const Icon(Icons.play_arrow_rounded,
                              color: Colors.white, size: 32),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Нажмите, чтобы продолжить',
                          style: TextStyle(
                              fontSize: 13,
                              color: textSecondary,
                              fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            bottom: 80 + reelsPad,
            left: 16,
            right: 16,
            child: IgnorePointer(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    v.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    v.author,
                    style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFFDCDDE1),
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _catalogScreen() {
    return SafeArea(
      top: true,
      bottom: false,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: bgColor.withOpacity(0.85),
              border: Border(
                  bottom:
                      BorderSide(color: Colors.white.withOpacity(0.1))),
            ),
            child: const Center(
              child: Text(
                'Каталог',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.white),
              ),
            ),
          ),
          if (!_inviteBannerDismissed)
            _buildInviteBanner(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 110),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 20, horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.02),
                        border: Border(
                          bottom: BorderSide(
                              color: Colors.white.withOpacity(0.06)),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _neonAction(
                              Icons.person_outline_rounded, 'Профиль'),
                          const SizedBox(width: 40),
                          _neonAction(Icons.chat_bubble_outline_rounded,
                              'Чат'),
                        ],
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 20, 16, 12),
                    child: Text(
                      'Информация и опции',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: navIconIdle,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        _menuCard(
                          icon: Icons.shield_outlined,
                          title: 'Правообладателям / DMCA',
                          trailing: const Icon(
                              Icons.open_in_new_rounded,
                              color: navIconIdle,
                              size: 20),
                          onTap: () =>
                              _openLink('https://kuzat.ru/dmca'),
                        ),
                        _menuCard(
                          icon: Icons.privacy_tip_outlined,
                          title: 'Политика конфиденциальности',
                          trailing: const Icon(
                              Icons.open_in_new_rounded,
                              color: navIconIdle,
                              size: 20),
                          onTap: () => _openLink(
                              'https://kuzat.ru/privacy'),
                        ),
                        _menuCard(
                          icon: Icons.mail_outline_rounded,
                          title: 'Связаться с нами',
                          trailing: const Icon(
                              Icons.chevron_right_rounded,
                              color: navIconIdle,
                              size: 20),
                          onTap: () => _openLink(
                              'mailto:ceonoyob@gmail.com'),
                        ),
                        _menuCard(
                          icon: Icons.history_rounded,
                          title: 'История просмотров',
                          trailing: const Icon(
                              Icons.chevron_right_rounded,
                              color: navIconIdle,
                              size: 20),
                          onTap: _showHistorySheet,
                        ),
                        _menuCard(
                          icon: Icons.add_circle_outline_rounded,
                          title: 'Предложить видео',
                          trailing: const Icon(
                              Icons.chevron_right_rounded,
                              color: navIconIdle,
                              size: 20),
                          onTap: _suggestVideoDialog,
                        ),
                        _menuCard(
                          icon: Icons.share_outlined,
                          title: 'Поделиться приложением',
                          trailing: const Icon(
                              Icons.chevron_right_rounded,
                              color: navIconIdle,
                              size: 20),
                          onTap: _shareApp,
                        ),
                        _menuCard(
                          icon: Icons.star_outline_rounded,
                          title: 'Оценить приложение',
                          trailing: const Icon(
                              Icons.chevron_right_rounded,
                              color: navIconIdle,
                              size: 20),
                          onTap: _rateApp,
                        ),
                        const SizedBox(height: 24),
                        GestureDetector(
                          onTap: _openAdminLogin,
                          child: Column(
                            children: [
                              const Text(
                                'Вход для администратора',
                                style: TextStyle(
                                    fontSize: 12, color: textMuted),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'TANHO v$appVersion (36)',
                                style: const TextStyle(
                                    fontSize: 11, color: textMuted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _neonAction(IconData icon, String label) {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF14121F),
            border: Border.all(
                color: secondaryPurple.withOpacity(0.6), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: secondaryPurple.withOpacity(0.6),
                blurRadius: 18,
              ),
            ],
          ),
          child: Icon(icon, color: secondaryPurple, size: 24),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFFDCDDE1)),
        ),
        const SizedBox(height: 6),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: secondaryPurple.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
            border:
                Border.all(color: secondaryPurple.withOpacity(0.4)),
          ),
          child: const Text(
            'СКОРО',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: secondaryPurple,
              letterSpacing: 0.6,
            ),
          ),
        ),
      ],
    );
  }

  Widget _menuCard({
    required IconData icon,
    required String title,
    required Widget trailing,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          border:
              Border.all(color: Colors.white.withOpacity(0.08)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: secondaryPurple.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: secondaryPurple, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white),
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }

  void _openAdminLogin() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminLoginScreen(
          onSuccess: () {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => AdminPanelScreen(
                  videos: List.of(_playlist),
                  onChanged: _applyAdminToPlaylist,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<List<VideoItem>> _getHistory() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final List<String> cur =
          prefs.getStringList(historyPrefsKey) ?? [];
      final List<VideoItem> out = [];
      for (final String raw in cur) {
        try {
          final dynamic d = jsonDecode(raw);
          if (d is Map<String, dynamic>) {
            final String embed = '${d['embedUrl'] ?? ''}';
            if (embed.isEmpty) continue;
            out.add(VideoItem(
              title: '${d['title'] ?? 'Без названия'}',
              author: 'VK Video',
              stats: '${d['views'] ?? 'VK Video'}',
              views: '${d['views'] ?? 'VK Video'}',
              duration: '${d['duration'] ?? ''}',
              durationSec: d['durationSec'] is int
                  ? d['durationSec'] as int
                  : int.tryParse('${d['durationSec'] ?? 0}') ?? 0,
              thumb: '${d['thumb'] ?? ''}',
              embedUrl: embed,
              player: '${d['player'] ?? embed}',
              genre: '${d['genre'] ?? ''}',
              direct: d['direct'] == true,
            ));
          }
        } catch (_) {}
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  void _showHistorySheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161820),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'История просмотров',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: const Icon(Icons.close_rounded,
                          color: navIconIdle, size: 22),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: FutureBuilder<List<VideoItem>>(
                    future: _getHistory(),
                    builder: (c, snap) {
                      if (!snap.hasData) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: CircularProgressIndicator(
                                color: secondaryPurple),
                          ),
                        );
                      }
                      final List<VideoItem> items = snap.data!;
                      if (items.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                            child: Text(
                              'Вы ещё ничего не смотрели',
                              style: TextStyle(
                                  color: textMuted, fontSize: 14),
                            ),
                          ),
                        );
                      }
                      return ListView.separated(
                        shrinkWrap: true,
                        itemCount: items.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 12),
                        itemBuilder: (c2, i) {
                          final VideoItem hv = items[i];
                          return GestureDetector(
                            onTap: () {
                              Navigator.pop(ctx);
                              _openShortsFromList(items, i);
                            },
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius:
                                      BorderRadius.circular(10),
                                  child: Image.network(
                                    thumbProxy(hv.thumb),
                                    width: 96,
                                    height: 54,
                                    fit: BoxFit.cover,
                                    errorBuilder:
                                        (c3, err, stack) {
                                      return Container(
                                        width: 96,
                                        height: 54,
                                        color: placeholderPurple,
                                        child: const Icon(
                                          Icons.play_circle_fill,
                                          color: secondaryPurple,
                                          size: 24,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        hv.title,
                                        maxLines: 2,
                                        overflow:
                                            TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight:
                                                FontWeight.w600,
                                            color: Colors.white,
                                            height: 1.3),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        hv.views,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: textMuted),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                    Icons.play_arrow_rounded,
                                    color: secondaryPurple,
                                    size: 24),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _suggestVideoDialog() {
    final TextEditingController linkCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          backgroundColor: const Color(0xFF161820),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Предложить видео',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Вставь ссылку на видео VK — после проверки оно появится в ленте.',
                style:
                    TextStyle(color: textSecondary, height: 1.5),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: linkCtrl,
                style: const TextStyle(
                    color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'https://vk.com/video...',
                  hintStyle:
                      const TextStyle(color: navIconIdle),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.08),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена',
                  style: TextStyle(color: textMuted)),
            ),
            TextButton(
              onPressed: () async {
                final String link = linkCtrl.text.trim();
                if (link.isEmpty) return;
                Navigator.pop(context);
                try {
                  final http.Response resp = await http
                      .post(
                        Uri.parse(
                            '$adminApiBase/api/suggest'),
                        headers: {
                          'Content-Type': 'application/json'
                        },
                        body: jsonEncode({'url': link}),
                      )
                      .timeout(const Duration(seconds: 10));
                  if (!mounted) return;
                  final bool ok = resp.statusCode == 200;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(ok
                          ? 'Спасибо! Видео отправлено на проверку.'
                          : 'Не получилось отправить. Попробуй позже.'),
                      backgroundColor: surfaceColor,
                    ),
                  );
                } catch (_) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          'Нет связи. Попробуй позже.'),
                      backgroundColor: surfaceColor,
                    ),
                  );
                }
              },
              child: const Text('Отправить',
                  style: TextStyle(color: secondaryPurple)),
            ),
          ],
        );
      },
    );
  }
}

class CustomHtmlAdScreen extends StatelessWidget {
  const CustomHtmlAdScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: InAppWebView(
                initialData: InAppWebViewInitialData(
                  data: adminStore.customHtml,
                ),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  domStorageEnabled: true,
                  mediaPlaybackRequiresUserGesture: false,
                  transparentBackground: true,
                ),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(50),
                    border: Border.all(
                        color: Colors.white.withOpacity(0.3)),
                  ),
                  child: const Icon(Icons.close_rounded,
                      color: Colors.white, size: 22),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AdminLoginScreen extends StatefulWidget {
  final VoidCallback onSuccess;
  const AdminLoginScreen({super.key, required this.onSuccess});
  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final TextEditingController _passCtrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _passCtrl.dispose();
    super.dispose();
  }

  bool _busy = false;

  void _try() async {
    final String pass = _passCtrl.text.trim();
    if (pass.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    bool ok = pass == adminStore.adminPass;
    if (!ok) {
      try {
        final http.Response resp = await http
            .post(
              Uri.parse('$adminApiBase/api/admin/login'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'token': pass}),
            )
            .timeout(const Duration(seconds: 10));
        final dynamic data = jsonDecode(resp.body);
        ok = resp.statusCode == 200 &&
            data is Map &&
            data['success'] == true;
      } catch (_) {
        ok = false;
      }
    }
    if (!mounted) return;
    if (ok) {
      adminStore.adminPass = pass;
      widget.onSuccess();
    } else {
      setState(() {
        _busy = false;
        _error = 'Неверный пароль';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: const Color(0xFF161820),
        foregroundColor: Colors.white,
        title: const Text('Вход для администратора'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _passCtrl,
              obscureText: true,
              onSubmitted: (_) => _try(),
              style:
                  const TextStyle(color: Colors.white, fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Пароль',
                hintStyle: const TextStyle(color: navIconIdle),
                filled: true,
                fillColor: Colors.white.withOpacity(0.08),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 16),
            GestureDetector(
              onTap: _busy ? null : _try,
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [primaryPurple, secondaryPurple],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: _busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Войти',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AdminPanelScreen extends StatefulWidget {
  final List<VideoItem> videos;
  final VoidCallback onChanged;
  const AdminPanelScreen(
      {super.key, required this.videos, required this.onChanged});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  int _tab = 0;
  String _query = '';
  late TextEditingController _feedEveryCtrl;
  late TextEditingController _reelsEveryCtrl;
  late TextEditingController _feedBlockCtrl;
  late TextEditingController _reelsBlockCtrl;
  late TextEditingController _versionCtrl;
  late TextEditingController _newPassCtrl;
  late TextEditingController _playerEveryCtrl;
  late bool _yandexOn;
  late bool _forceOn;
  late String _playerMode;
  late String _videoMode;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _feedEveryCtrl =
        TextEditingController(text: '${adminStore.feedAdEvery}');
    _reelsEveryCtrl =
        TextEditingController(text: '${adminStore.reelsAdEvery}');
    _feedBlockCtrl = TextEditingController(text: adminStore.feedBlockId);
    _reelsBlockCtrl =
        TextEditingController(text: adminStore.reelsBlockId);
    _versionCtrl =
        TextEditingController(text: adminStore.latestVersion);
    _newPassCtrl = TextEditingController();
    _playerEveryCtrl =
        TextEditingController(text: '${adminStore.playerAdEvery}');
    _yandexOn = adminStore.yandexEnabled;
    _forceOn = adminStore.forceUpdate;
    _playerMode = adminStore.playerAdMode;
    _videoMode = adminStore.videoSource;
  }

  @override
  void dispose() {
    _feedEveryCtrl.dispose();
    _reelsEveryCtrl.dispose();
    _feedBlockCtrl.dispose();
    _reelsBlockCtrl.dispose();
    _versionCtrl.dispose();
    _newPassCtrl.dispose();
    _playerEveryCtrl.dispose();
    super.dispose();
  }

  void _refresh() {
    widget.onChanged();
    setState(() {});
  }

  Future<void> _saveSettings() async {
    setState(() => _saving = true);
    adminStore.yandexEnabled = _yandexOn;
    adminStore.feedAdEvery =
        int.tryParse(_feedEveryCtrl.text) ?? adminStore.feedAdEvery;
    adminStore.reelsAdEvery =
        int.tryParse(_reelsEveryCtrl.text) ?? adminStore.reelsAdEvery;
    adminStore.feedBlockId = _feedBlockCtrl.text.trim();
    adminStore.reelsBlockId = _reelsBlockCtrl.text.trim();
    adminStore.latestVersion = _versionCtrl.text.trim().isNotEmpty
        ? _versionCtrl.text.trim()
        : adminStore.latestVersion;
    adminStore.forceUpdate = _forceOn;
    final String newPass = _newPassCtrl.text.trim();
    if (newPass.length >= 4) {
      try {
        await http
            .post(
              Uri.parse('$adminApiBase/api/admin/config'),
              headers: {
                'Content-Type': 'application/json',
              },
              body: jsonEncode({
                'token': adminStore.adminPass,
                'settings': {'adminAppPass': newPass}
              }),
            )
            .timeout(const Duration(seconds: 10));
      } catch (_) {}
      adminStore.adminPass = newPass;
      _newPassCtrl.clear();
    }
    adminStore.playerAdMode = _playerMode;
    adminStore.playerAdEvery =
        int.tryParse(_playerEveryCtrl.text) ?? adminStore.playerAdEvery;
    adminStore.videoSource = _videoMode;
    await adminStore.persist();
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Настройки сохранены локально'),
        backgroundColor: surfaceColor,
      ),
    );
  }

  void _quickAddDialog() {
    final TextEditingController linkCtrl = TextEditingController();
    bool busy = false;
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setD) {
            return AlertDialog(
              backgroundColor: const Color(0xFF161820),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Text(
                'Добавить видео',
                style: TextStyle(color: Colors.white),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: linkCtrl,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: 'https://vk.com/video...',
                      hintStyle: TextStyle(color: textMuted),
                    ),
                  ),
                  if (busy)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: secondaryPurple,
                          strokeWidth: 2,
                        ),
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Отмена',
                      style: TextStyle(color: textMuted)),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () async {
                          final String link =
                              linkCtrl.text.trim();
                          if (link.isEmpty) return;
                          final messenger =
                              ScaffoldMessenger.of(context);
                          final navigator = Navigator.of(ctx);
                          setD(() => busy = true);
                          try {
                            final http.Response resp = await http
                                .post(
                                  Uri.parse(
                                      '$adminApiBase/api/catalog/quick-add'),
                                  headers: {
                                    'Content-Type':
                                        'application/json',
                                    'X-Admin-Pass':
                                        adminStore.adminPass,
                                  },
                                  body: jsonEncode(
                                      {'url': link}),
                                )
                                .timeout(
                                    const Duration(seconds: 45));
                            navigator.pop();
                            final dynamic data =
                                jsonDecode(resp.body);
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(data is Map &&
                                        data['success'] == true
                                    ? 'Добавлено: ${(data['item']?['title'] ?? 'видео')}'
                                    : 'Не распозналось: ${(data is Map ? data['error'] : '') ?? ''}'),
                                backgroundColor: surfaceColor,
                              ),
                            );
                            _refresh();
                          } catch (_) {
                            navigator.pop();
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Нет связи. Попробуй позже.'),
                                backgroundColor: surfaceColor,
                              ),
                            );
                          }
                        },
                  child: const Text('Добавить',
                      style:
                          TextStyle(color: secondaryPurple)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: const Color(0xFF161820),
        foregroundColor: Colors.white,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Text('☰',
                style: TextStyle(fontSize: 22, color: Colors.white)),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: const Text(
          'TANHO Admin',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      drawer: Drawer(
        backgroundColor: const Color(0xFF161820),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'TANHO Admin',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Colors.white),
                ),
              ),
              _drawerItem(0, Icons.dashboard_rounded, 'Дашборд'),
              _drawerItem(1, Icons.video_library_rounded, 'Все видео'),
              _drawerItem(2, Icons.settings_rounded, 'Настройки'),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  firebaseReady
                      ? 'Firestore: подключено'
                      : 'Локальный режим',
                  style: const TextStyle(
                      fontSize: 11, color: textMuted),
                ),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: _tab == 0
            ? _dashboard()
            : _tab == 1
                ? _allVideos()
                : _settingsTab(),
      ),
    );
  }

  Widget _drawerItem(int index, IconData icon, String label) {
    final bool active = _tab == index;
    return ListTile(
      leading: Icon(icon,
          color: active ? secondaryPurple : navIconIdle),
      title: Text(
        label,
        style: TextStyle(
            color: active ? Colors.white : textSecondary,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500),
      ),
      selected: active,
      selectedTileColor: secondaryPurple.withOpacity(0.12),
      onTap: () {
        Navigator.pop(context);
        setState(() => _tab = index);
      },
    );
  }

  Widget _dashboard() {
    final int users = adminStore.fsUsers > 0 ? adminStore.fsUsers : 1;
    final int views = adminStore.fsViews + adminStore.localViews;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _metricCard('👤', 'Всего пользователей', '$users'),
        _metricCard('👁️', 'Всего просмотров', '$views'),
        _metricCard('🎥', 'Видео в базе / заблокировано',
            '${widget.videos.length} / ${adminStore.blacklist.length}'),
      ],
    );
  }

  Widget _metricCard(String emoji, String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        border:
            Border.all(color: Colors.white.withOpacity(0.08)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 30)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 13, color: textMuted)),
                const SizedBox(height: 4),
                Text(value,
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _allVideos() {
    final String q = _query.toLowerCase().trim();
    final List<VideoItem> list = widget.videos.where((v) {
      if (q.isEmpty) return true;
      return v.title.toLowerCase().contains(q) ||
          v.videoKey.toLowerCase().contains(q);
    }).toList();
    final List<String> blocked = adminStore.blacklist.toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: GestureDetector(
            onTap: _quickAddDialog,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [primaryPurple, secondaryPurple],
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Center(
                child: Text(
                  '＋ Добавить видео по ссылке',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Поиск по названию или ID...',
              hintStyle:
                  const TextStyle(color: navIconIdle, fontSize: 14),
              prefixIcon: const Icon(Icons.search_rounded,
                  color: secondaryPurple),
              filled: true,
              fillColor: Colors.white.withOpacity(0.08),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              ...list.map(_adminVideoRow),
              if (blocked.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Заблокированные',
                    style: TextStyle(
                        fontSize: 12, color: textMuted),
                  ),
                ),
                ...blocked.map(_blockedRow),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _blockedRow(String key) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.06),
        border: Border.all(color: Colors.red.withOpacity(0.25)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              key,
              style:
                  const TextStyle(fontSize: 13, color: textSecondary),
            ),
          ),
          TextButton(
            onPressed: () async {
              await adminStore.persistBlacklist(key, false);
              _refresh();
            },
            child: const Text('Вернуть',
                style: TextStyle(color: secondaryPurple)),
          ),
        ],
      ),
    );
  }

  Widget _adminVideoRow(VideoItem v) {
    final String key = v.videoKey;
    final bool blocked = adminStore.isBlocked(key);
    final bool hidden = adminStore.isHidden(key);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        border:
            Border.all(color: Colors.white.withOpacity(0.08)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  thumbProxy(v.thumb),
                  width: 88,
                  height: 50,
                  fit: BoxFit.cover,
                  errorBuilder: (c, err, stack) {
                    return Container(
                      width: 88,
                      height: 50,
                      color: placeholderPurple,
                      child: const Icon(
                        Icons.play_circle_fill,
                        color: secondaryPurple,
                        size: 22,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      v.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      key,
                      style: const TextStyle(
                          fontSize: 11, color: textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: () async {
                  await adminStore.persistBlacklist(key, !blocked);
                  _refresh();
                },
                child: Text(blocked ? 'Вернуть' : 'Удалить',
                    style: const TextStyle(
                        color: Colors.red, fontSize: 12)),
              ),
              TextButton(
                onPressed: () async {
                  final Map<String, dynamic>? cur =
                      adminStore.custom[key];
                  adminStore.custom[key] = {
                    ...(cur ?? {}),
                    'is_hidden': !hidden,
                  };
                  await adminStore.persistCustom(key);
                  _refresh();
                },
                child: Text(hidden ? 'Показать' : 'Скрыть',
                    style: const TextStyle(
                        color: Colors.orange, fontSize: 12)),
              ),
              TextButton(
                onPressed: () async {
                  final messenger =
                      ScaffoldMessenger.of(context);
                  try {
                    final http.Response resp = await http
                        .post(
                          Uri.parse(
                              '$adminApiBase/api/catalog/quick-add'),
                          headers: {
                            'Content-Type': 'application/json',
                            'X-Admin-Pass':
                                adminStore.adminPass,
                          },
                          body: jsonEncode({
                            'url':
                                'https://vk.com/video$key'
                          }),
                        )
                        .timeout(const Duration(seconds: 45));
                    final dynamic data =
                        jsonDecode(resp.body);
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(data is Map &&
                                data['success'] == true
                            ? 'Обложка обновлена'
                            : 'Не получилось'),
                        backgroundColor: surfaceColor,
                      ),
                    );
                    _refresh();
                  } catch (_) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Нет связи'),
                        backgroundColor: surfaceColor,
                      ),
                    );
                  }
                },
                child: const Text('Обновить обложку',
                    style: TextStyle(
                        color: secondaryPurple, fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _settingsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _setSwitch('Реклама Яндекса', _yandexOn,
            (v) => setState(() => _yandexOn = v)),
        _setField('Лента: каждые N карточек', _feedEveryCtrl),
        _setField('Reels: каждые N свайпов', _reelsEveryCtrl),
        _setField('Yandex Block ID (лента)', _feedBlockCtrl),
        _setField('Yandex Block ID (Reels)', _reelsBlockCtrl),
        _setField('Актуальная версия', _versionCtrl),
        _setSwitch('Force Update', _forceOn,
            (v) => setState(() => _forceOn = v)),
        _setField('Новый пароль админки', _newPassCtrl),
        _setField('Плеер: реклама каждый N-й', _playerEveryCtrl),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('Реклама в плеере',
              style: TextStyle(color: textSecondary, fontSize: 13)),
        ),
        Row(
          children: [
            _modeChip('Выкл', _playerMode == 'off',
                () => setState(() => _playerMode = 'off')),
            const SizedBox(width: 8),
            _modeChip('HTML', _playerMode == 'html',
                () => setState(() => _playerMode = 'html')),
            const SizedBox(width: 8),
            _modeChip('Yandex', _playerMode == 'yandex',
                () => setState(() => _playerMode = 'yandex')),
          ],
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('Режим получения видео',
              style: TextStyle(color: textSecondary, fontSize: 13)),
        ),
        Row(
          children: [
            _modeChip('VK API', _videoMode == 'vkapi',
                () => setState(() => _videoMode = 'vkapi')),
            const SizedBox(width: 8),
            _modeChip('Парсер', _videoMode == 'parser',
                () => setState(() => _videoMode = 'parser')),
          ],
        ),
        const SizedBox(height: 20),
        GestureDetector(
          onTap: _saving ? null : _saveSettings,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [primaryPurple, secondaryPurple],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'Сохранить',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _setSwitch(
      String label, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style:
                  const TextStyle(color: Colors.white, fontSize: 14)),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: secondaryPurple,
          ),
        ],
      ),
    );
  }

  Widget _setField(String label, TextEditingController ctrl) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: textSecondary, fontSize: 13)),
          const SizedBox(height: 6),
          TextField(
            controller: ctrl,
            style: const TextStyle(
                color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white.withOpacity(0.08),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeChip(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: active
              ? secondaryPurple.withOpacity(0.25)
              : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: active
                  ? secondaryPurple
                  : Colors.white.withOpacity(0.12)),
        ),
        child: Text(
          '${active ? '✓ ' : ''}$label',
          style: TextStyle(
              color: active ? Colors.white : textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

