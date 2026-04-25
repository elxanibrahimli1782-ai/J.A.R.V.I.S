import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF000811),
  ));
  runApp(const JarvisApp());
}

// ── Renkler ──────────────────────────────────────────────
const kBlue = Color(0xFF00D4FF);
const kBlue2 = Color(0xFF0099CC);
const kGold = Color(0xFFFFD700);
const kRed = Color(0xFFFF4455);
const kGreen = Color(0xFF00FF88);
const kBg = Color(0xFF000811);
const kPanel = Color(0xFF001932);

// ── Uygulama paket isimleri ───────────────────────────────
const Map<String, String> kAppPackages = {
  'chrome': 'com.android.chrome',
  'google chrome': 'com.android.chrome',
  'youtube': 'com.google.android.youtube',
  'whatsapp': 'com.whatsapp',
  'instagram': 'com.instagram.android',
  'twitter': 'com.twitter.android',
  'x': 'com.twitter.android',
  'gmail': 'com.google.android.gm',
  'haritalar': 'com.google.android.apps.maps',
  'maps': 'com.google.android.apps.maps',
  'spotify': 'com.spotify.music',
  'kamera': 'com.android.camera2',
  'camera': 'com.android.camera2',
  'galeri': 'com.google.android.apps.photos',
  'ayarlar': 'com.android.settings',
  'settings': 'com.android.settings',
  'telefon': 'com.google.android.dialer',
  'calculator': 'com.android.calculator2',
  'hesap makinesi': 'com.android.calculator2',
  'takvim': 'com.google.android.calendar',
  'calendar': 'com.google.android.calendar',
  'play store': 'com.android.vending',
};

class JarvisApp extends StatelessWidget {
  const JarvisApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'J.A.R.V.I.S.',
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark().copyWith(
      scaffoldBackgroundColor: kBg,
      colorScheme: const ColorScheme.dark(primary: kBlue, secondary: kGold),
    ),
    home: const JarvisScreen(),
  );
}

// ── Model ─────────────────────────────────────────────────
class ChatMessage {
  final String role; // 'user' | 'jarvis'
  final String text;
  final DateTime time;
  ChatMessage({required this.role, required this.text}) : time = DateTime.now();
}

// ── Ana Ekran ─────────────────────────────────────────────
class JarvisScreen extends StatefulWidget {
  const JarvisScreen({super.key});
  @override
  State<JarvisScreen> createState() => _JarvisScreenState();
}

class _JarvisScreenState extends State<JarvisScreen> with TickerProviderStateMixin {
  static const _channel = MethodChannel('com.jarvis/system');
  static const _apiKey = 'YOUR_ANTHROPIC_API_KEY'; // <-- buraya API key

  final _stt = SpeechToText();
  final _tts = FlutterTts();
  final _scroll = ScrollController();
  final _textCtrl = TextEditingController();
  final _focusNode = FocusNode();

  List<ChatMessage> _msgs = [];
  List<Map<String, dynamic>> _conv = [];
  bool _listening = false;
  bool _loading = false;
  bool _webSearch = false;
  bool _screenWatch = false;
  bool _accessibilityOk = false;
  String _screenText = '';
  Timer? _screenTimer;

  late AnimationController _arcCtrl;
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _arcCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _initTts();
    _checkPermissions();
    Future.delayed(const Duration(milliseconds: 500), _showWelcome);
  }

  @override
  void dispose() {
    _arcCtrl.dispose();
    _pulseCtrl.dispose();
    _screenTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('tr-TR');
    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(0.85);
  }

  Future<void> _checkPermissions() async {
    await Permission.microphone.request();
    final ok = await _channel.invokeMethod<bool>('isAccessibilityEnabled') ?? false;
    setState(() => _accessibilityOk = ok);
  }

  void _showWelcome() {
    _addJarvisMsg(
      'Sistemler aktif, Bay Stark. J.A.R.V.I.S. hizmetinizde. '
      'Uygulama açma, ekran okuma ve sesli komut özellikleri hazır. '
      'Ne yapmamı istersiniz?'
    );
  }

  void _addJarvisMsg(String text) {
    setState(() => _msgs.add(ChatMessage(role: 'jarvis', text: text)));
    _scrollDown();
    _speak(text);
  }

  void _addUserMsg(String text) {
    setState(() => _msgs.add(ChatMessage(role: 'user', text: text)));
    _scrollDown();
  }

  void _scrollDown() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _speak(String text) async {
    final clean = text.replaceAll(RegExp(r'```[\s\S]*?```'), 'Kod bloğu.')
        .replaceAll('**', '').replaceAll('*', '');
    await _tts.speak(clean.length > 400 ? clean.substring(0, 400) : clean);
  }

  // ── Ses Dinleme ──────────────────────────────────────────
  Future<void> _toggleListen() async {
    if (_listening) {
      await _stt.stop();
      setState(() => _listening = false);
      return;
    }
    final avail = await _stt.initialize(onError: (_) => setState(() => _listening = false));
    if (!avail) {
      _addJarvisMsg('Mikrofon erişimi sağlanamadı.');
      return;
    }
    setState(() => _listening = true);
    await _stt.listen(
      localeId: 'tr_TR',
      onResult: (r) {
        if (r.finalResult) {
          setState(() => _listening = false);
          final text = r.recognizedWords.trim();
          if (text.isNotEmpty) _processInput(text);
        }
      },
    );
  }

  // ── Ekran İzleme ─────────────────────────────────────────
  void _toggleScreenWatch() {
    if (_screenWatch) {
      _screenTimer?.cancel();
      setState(() { _screenWatch = false; _screenText = ''; });
      return;
    }
    if (!_accessibilityOk) {
      _showAccessibilityDialog();
      return;
    }
    setState(() => _screenWatch = true);
    _screenTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      final text = await _channel.invokeMethod<String>('getScreenText') ?? '';
      if (text != _screenText && text.isNotEmpty) {
        _screenText = text;
        _analyzeScreen(text);
      }
    });
    _addJarvisMsg('Ekran izleme aktif. Ekranınızda matematik, metin veya analiz gerektiren içerik gördüğümde otomatik işleyeceğim.');
  }

  Future<void> _analyzeScreen(String screenContent) async {
    // Matematik veya önemli içerik var mı?
    final hasMath = RegExp(r'[\d\+\-\*\/\=\(\)%√∫∑πx²³]+').hasMatch(screenContent);
    final isLong = screenContent.length > 200;

    if (!hasMath && !isLong) return;

    final prompt = hasMath
        ? 'Ekranda şu içerik var: "$screenContent"\n\nEğer matematik sorusu veya denklem varsa çöz. Yoksa kısa bir özet ver.'
        : 'Ekranda şu içerik var: "$screenContent"\n\nBu içeriği çok kısa özetle (1-2 cümle).';

    final reply = await _callClaudeRaw(prompt);
    if (reply.isNotEmpty) {
      _addJarvisMsg('📱 Ekran analizi: $reply');
    }
  }

  // ── Komut İşleme ─────────────────────────────────────────
  Future<void> _processInput(String input) async {
    _addUserMsg(input);
    final lower = input.toLowerCase().trim();

    // 1. Uygulama açma
    if (_tryOpenApp(lower)) return;

    // 2. Sistem komutları
    if (_trySystemCommand(lower)) return;

    // 3. Ekran içeriği analizi
    if (lower.contains('ekranı analiz') || lower.contains('ekranda ne var')) {
      final text = await _channel.invokeMethod<String>('getScreenText') ?? '';
      if (text.isEmpty) {
        _addJarvisMsg('Ekranda okunabilir metin bulunamadı.');
      } else {
        _processInput('Şu ekran içeriğini analiz et: $text');
      }
      return;
    }

    // 4. Claude AI
    await _callClaude(input);
  }

  bool _tryOpenApp(String lower) {
    for (final entry in kAppPackages.entries) {
      if (lower.contains(entry.key) &&
          (lower.contains('aç') || lower.contains('başlat') || lower.contains('open'))) {
        _openApp(entry.value, entry.key);
        return true;
      }
    }
    // URL açma
    if (lower.contains('aç') && lower.contains('.com') || lower.contains('http')) {
      final urlMatch = RegExp(r'https?://\S+|[\w-]+\.com\S*').firstMatch(lower);
      if (urlMatch != null) {
        var url = urlMatch.group(0)!;
        if (!url.startsWith('http')) url = 'https://$url';
        _openUrl(url);
        return true;
      }
    }
    return false;
  }

  bool _trySystemCommand(String lower) {
    if (lower.contains('geri') && (lower.contains('git') || lower.contains('dön'))) {
      _channel.invokeMethod('pressBack');
      _addJarvisMsg('Geri gidildi.');
      return true;
    }
    if (lower.contains('ana ekran') || lower.contains('home')) {
      _channel.invokeMethod('pressHome');
      _addJarvisMsg('Ana ekrana gidildi.');
      return true;
    }
    if (lower.contains('son uygulamalar') || lower.contains('recent')) {
      _channel.invokeMethod('pressRecents');
      _addJarvisMsg('Son uygulamalar açıldı.');
      return true;
    }
    return false;
  }

  Future<void> _openApp(String package, String name) async {
    _addJarvisMsg('$name açılıyor...');
    final ok = await _channel.invokeMethod<bool>('openApp', {'package': package}) ?? false;
    if (!ok) _addJarvisMsg('$name bulunamadı. Yüklü olmayabilir.');
  }

  Future<void> _openUrl(String url) async {
    _addJarvisMsg('$url açılıyor...');
    await _channel.invokeMethod('openUrl', {'url': url});
  }

  // ── Claude API ───────────────────────────────────────────
  Future<void> _callClaude(String userInput) async {
    setState(() => _loading = true);

    _conv.add({'role': 'user', 'content': userInput});

    try {
      final body = {
        'model': 'claude-sonnet-4-20250514',
        'max_tokens': 1000,
        'system': _buildSystemPrompt(),
        'messages': _conv,
      };

      if (_webSearch) {
        body['tools'] = [{'type': 'web_search_20250305', 'name': 'web_search'}];
      }

      final res = await http.post(
        Uri.parse('https://api.anthropic.com/v1/messages'),
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': _apiKey,
          'anthropic-version': '2023-06-01',
          if (_webSearch) 'anthropic-beta': 'web-search-2025-03-05',
        },
        body: jsonEncode(body),
      );

      final data = jsonDecode(utf8.decode(res.bodyBytes));
      final reply = (data['content'] as List)
          .where((c) => c['type'] == 'text')
          .map((c) => c['text'] as String)
          .join('\n');

      _conv.add({'role': 'assistant', 'content': reply});
      _addJarvisMsg(reply.isNotEmpty ? reply : 'Sistem analiz tamamlandı.');
    } catch (e) {
      _addJarvisMsg('Bağlantı hatası: $e');
      _conv.removeLast();
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<String> _callClaudeRaw(String prompt) async {
    try {
      final res = await http.post(
        Uri.parse('https://api.anthropic.com/v1/messages'),
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': _apiKey,
          'anthropic-version': '2023-06-01',
        },
        body: jsonEncode({
          'model': 'claude-sonnet-4-20250514',
          'max_tokens': 300,
          'messages': [{'role': 'user', 'content': prompt}],
        }),
      );
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      return (data['content'] as List)
          .where((c) => c['type'] == 'text')
          .map((c) => c['text'] as String)
          .join('');
    } catch (_) { return ''; }
  }

  String _buildSystemPrompt() => '''
Sen J.A.R.V.I.S. (Just A Rather Very Intelligent System) adlı Android asistanısın.

YETENEKLERİN (gerçek):
- Android uygulamalarını açabilirsin (Chrome, YouTube, WhatsApp vs.)
- Ekran içeriğini okuyup analiz edebilirsin
- Matematik sorularını çözebilirsin
- Web araması yapabilirsin
- Kod yazabilirsin
- Sesli komutları anlarsın

KİŞİLİK: Kibarca ve saygılı, kullanıcıya "Bay Stark" de. Türkçe konuş. Net ve özlü ol.

Uygulama açma için "X açılıyor..." de ve sisteme bırak.
Matematik gördüğünde adım adım çöz.
''';

  void _showAccessibilityDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kPanel,
        title: const Text('Erişilebilirlik İzni', style: TextStyle(color: kBlue, fontFamily: 'Orbitron')),
        content: const Text(
          'Ekran izleme için Erişilebilirlik iznine ihtiyaç var.\n\nAyarlar → Erişilebilirlik → JARVIS → Aç',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () { Navigator.pop(context); _channel.invokeMethod('openAccessibilitySettings'); },
            child: const Text('Ayarları Aç', style: TextStyle(color: kBlue)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal', style: TextStyle(color: Colors.white38)),
          ),
        ],
      ),
    );
  }

  // ── Mesaj gönder ─────────────────────────────────────────
  void _send() {
    final t = _textCtrl.text.trim();
    if (t.isEmpty) return;
    _textCtrl.clear();
    _focusNode.unfocus();
    _processInput(t);
  }

  // ── BUILD ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: Stack(
        children: [
          _buildGrid(),
          SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                _buildMessages(),
                _buildToolbar(),
                _buildInput(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid() => Positioned.fill(
    child: CustomPaint(painter: _GridPainter()),
  );

  Widget _buildHeader() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFF00050C).withOpacity(0.95),
      border: Border(bottom: BorderSide(color: kBlue.withOpacity(0.15))),
    ),
    child: Row(
      children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('J.A.R.V.I.S.',
            style: GoogleFonts.orbitron(fontSize: 13, fontWeight: FontWeight.w900,
                color: kBlue, letterSpacing: 3,
                shadows: [Shadow(color: kBlue.withOpacity(0.6), blurRadius: 10)])),
          Text('Yapay Zeka Sistemi',
            style: TextStyle(fontSize: 9, color: kBlue.withOpacity(0.4), letterSpacing: 1.5)),
        ]),
        const Spacer(),
        // Arc Reactor
        AnimatedBuilder(
          animation: _arcCtrl,
          builder: (_, __) => SizedBox(
            width: 44, height: 44,
            child: Stack(alignment: Alignment.center, children: [
              Transform.rotate(
                angle: _arcCtrl.value * 2 * 3.14159,
                child: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: kBlue.withOpacity(0.6), width: 2),
                    boxShadow: [BoxShadow(color: kBlue.withOpacity(0.3), blurRadius: 10)],
                  ),
                ),
              ),
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: kBlue.withOpacity(0.3), width: 1),
                ),
              ),
              AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (_, __) => Container(
                  width: 12, height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(color: kBlue, blurRadius: 8 + _pulseCtrl.value * 12),
                    ],
                  ),
                ),
              ),
            ]),
          ),
        ),
        const Spacer(),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Row(children: [
            Container(width: 6, height: 6,
              decoration: BoxDecoration(shape: BoxShape.circle, color: kGreen,
                boxShadow: [BoxShadow(color: kGreen, blurRadius: 6)])),
            const SizedBox(width: 5),
            Text('AKTİF', style: TextStyle(fontSize: 9, color: kBlue.withOpacity(0.6), letterSpacing: 1)),
          ]),
          const SizedBox(height: 3),
          StreamBuilder(
            stream: Stream.periodic(const Duration(seconds: 1)),
            builder: (_, __) {
              final now = DateTime.now();
              return Text(
                '${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}',
                style: GoogleFonts.orbitron(fontSize: 10, color: kBlue.withOpacity(0.5)),
              );
            },
          ),
        ]),
      ],
    ),
  );

  Widget _buildMessages() => Expanded(
    child: _msgs.isEmpty
        ? _buildWelcome()
        : ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.all(12),
            itemCount: _msgs.length + (_loading ? 1 : 0),
            itemBuilder: (_, i) {
              if (i == _msgs.length) return _buildTyping();
              return _buildMsgItem(_msgs[i]);
            },
          ),
  );

  Widget _buildWelcome() => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      AnimatedBuilder(
        animation: _pulseCtrl,
        builder: (_, __) => Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: kBlue, width: 2),
            boxShadow: [BoxShadow(color: kBlue.withOpacity(0.3 + _pulseCtrl.value * 0.3), blurRadius: 20 + _pulseCtrl.value * 20)],
          ),
          child: Center(
            child: Container(
              width: 24, height: 24,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white,
                boxShadow: [BoxShadow(color: kBlue, blurRadius: 15)]),
            ),
          ),
        ),
      ),
      const SizedBox(height: 16),
      Text('J.A.R.V.I.S.', style: GoogleFonts.orbitron(fontSize: 18, fontWeight: FontWeight.w900,
          color: kBlue, letterSpacing: 4)),
      const SizedBox(height: 6),
      Text('Başlatılıyor...', style: TextStyle(color: kBlue.withOpacity(0.4), fontSize: 12, letterSpacing: 2)),
    ]),
  );

  Widget _buildMsgItem(ChatMessage msg) {
    final isJarvis = msg.role == 'jarvis';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isJarvis ? MainAxisAlignment.start : MainAxisAlignment.end,
        children: [
          if (isJarvis) ...[
            _avatar('🤖', kBlue),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isJarvis ? CrossAxisAlignment.start : CrossAxisAlignment.end,
              children: [
                Text(
                  isJarvis ? 'J.A.R.V.I.S.' : 'SİZ',
                  style: GoogleFonts.orbitron(fontSize: 8,
                      color: (isJarvis ? kBlue : kGold).withOpacity(0.4), letterSpacing: 1),
                ),
                const SizedBox(height: 3),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                  decoration: BoxDecoration(
                    color: isJarvis ? kPanel.withOpacity(0.85) : const Color(0xFF1A1000).withOpacity(0.6),
                    borderRadius: BorderRadius.circular(3),
                    border: Border(
                      left: isJarvis ? BorderSide(color: kBlue, width: 3) : BorderSide.none,
                      right: !isJarvis ? BorderSide(color: kGold, width: 3) : BorderSide.none,
                      top: BorderSide(color: (isJarvis ? kBlue : kGold).withOpacity(0.15)),
                      bottom: BorderSide(color: (isJarvis ? kBlue : kGold).withOpacity(0.15)),
                    ),
                  ),
                  child: Text(msg.text,
                    style: TextStyle(
                      color: isJarvis ? kBlue.withOpacity(0.92) : kGold.withOpacity(0.9),
                      fontSize: 13.5, height: 1.5, letterSpacing: 0.3,
                    ),
                    textAlign: isJarvis ? TextAlign.left : TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
          if (!isJarvis) ...[
            const SizedBox(width: 8),
            _avatar('👤', kGold),
          ],
        ],
      ),
    );
  }

  Widget _avatar(String emoji, Color color) => Container(
    width: 32, height: 32,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: color.withOpacity(0.35)),
      color: const Color(0xFF000F1E),
    ),
    child: Center(child: Text(emoji, style: const TextStyle(fontSize: 14))),
  );

  Widget _buildTyping() => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(children: [
      _avatar('🤖', kBlue),
      const SizedBox(width: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: kPanel.withOpacity(0.85),
          borderRadius: BorderRadius.circular(3),
          border: Border(left: BorderSide(color: kBlue, width: 3)),
        ),
        child: Row(children: List.generate(3, (i) =>
          AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (_, __) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 6, height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: kBlue.withOpacity(i == 1 ? _pulseCtrl.value : 0.4),
              ),
            ),
          ),
        )),
      ),
    ]),
  );

  Widget _buildToolbar() => Container(
    height: 44,
    decoration: BoxDecoration(
      color: const Color(0xFF000508).withOpacity(0.98),
      border: Border(top: BorderSide(color: kBlue.withOpacity(0.1))),
    ),
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      children: [
        _toolBtn('🌐 Web', _webSearch, () => setState(() => _webSearch = !_webSearch)),
        _toolBtn('📱 Ekran İzle', _screenWatch, _toggleScreenWatch),
        _toolBtn('⚙️ Erişilebilirlik', false, _showAccessibilityDialog),
        _toolBtn('🗑 Temizle', false, () {
          setState(() { _msgs.clear(); _conv.clear(); });
          _showWelcome();
        }),
      ],
    ),
  );

  Widget _toolBtn(String label, bool active, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(right: 7),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: active ? kBlue.withOpacity(0.15) : kPanel.withOpacity(0.5),
        border: Border.all(color: active ? kBlue : kBlue.withOpacity(0.2)),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Center(
        child: Text(label, style: TextStyle(
          fontSize: 11, color: active ? kBlue : kBlue.withOpacity(0.6),
          letterSpacing: 0.5,
        )),
      ),
    ),
  );

  Widget _buildInput() => Container(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
    color: const Color(0xFF000508).withOpacity(0.98),
    child: Row(children: [
      GestureDetector(
        onTap: _toggleListen,
        child: AnimatedBuilder(
          animation: _pulseCtrl,
          builder: (_, __) => Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _listening ? kRed.withOpacity(0.15) : kPanel,
              border: Border.all(
                color: _listening
                    ? kRed.withOpacity(0.5 + _pulseCtrl.value * 0.5)
                    : kBlue.withOpacity(0.25),
              ),
              boxShadow: _listening
                  ? [BoxShadow(color: kRed.withOpacity(0.3 + _pulseCtrl.value * 0.3), blurRadius: 14)]
                  : [],
            ),
            child: Center(child: Text(_listening ? '🔴' : '🎤', style: const TextStyle(fontSize: 18))),
          ),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: TextField(
          controller: _textCtrl,
          focusNode: _focusNode,
          style: TextStyle(color: kBlue.withOpacity(0.92), fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Komut girin...',
            hintStyle: TextStyle(color: kBlue.withOpacity(0.28), fontSize: 14),
            filled: true,
            fillColor: const Color(0xFF000F23),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: BorderSide(color: kBlue.withOpacity(0.22)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: BorderSide(color: kBlue.withOpacity(0.22)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: const BorderSide(color: kBlue),
            ),
          ),
          onSubmitted: (_) => _send(),
          maxLines: null,
        ),
      ),
      const SizedBox(width: 8),
      GestureDetector(
        onTap: _send,
        child: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [kBlue2, kBlue],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            boxShadow: [BoxShadow(color: kBlue.withOpacity(0.4), blurRadius: 14)],
          ),
          child: const Center(child: Icon(Icons.send, color: Colors.black, size: 20)),
        ),
      ),
    ]),
  );
}

// ── Grid Background Painter ───────────────────────────────
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF00D4FF).withOpacity(0.03)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 30) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += 30) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }
  @override
  bool shouldRepaint(_) => false;
}
