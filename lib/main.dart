import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const HissnAlWaqtApp());
}

class HissnAlWaqtApp extends StatelessWidget {
  const HissnAlWaqtApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'حصن الوقت',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0D1117),
        primaryColor: const Color(0xFF10B981),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF10B981),
          secondary: Color(0xFFD4AF37),
          surface: Color(0xFF161B22),
        ),
      ),
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        );
      },
      home: const MainHomeScreen(),
    );
  }
}

class DhikrItem {
  String id;
  String text;
  int targetCount;
  int timerSeconds;

  DhikrItem({
    required this.id,
    required this.text,
    required this.targetCount,
    required this.timerSeconds,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'targetCount': targetCount,
        'timerSeconds': timerSeconds,
      };

  factory DhikrItem.fromJson(Map<String, dynamic> json) => DhikrItem(
        id: json['id'],
        text: json['text'],
        targetCount: json['targetCount'],
        timerSeconds: json['timerSeconds'],
      );
}

class MainHomeScreen extends StatefulWidget {
  const MainHomeScreen({super.key});

  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> with WidgetsBindingObserver {
  static const platform = MethodChannel('com.elkahlaoui.hissn_alwaqt/blocker');

  int _currentIndex = 0;
  bool _isBlockerActive = false;
  bool _isTimerMode = false;
  int _graceMinutes = 15;
  int _totalTasbeehCount = 0;
  int _interceptedCount = 0;

  bool _hasUsagePermission = false;
  bool _hasOverlayPermission = false;

  TimeOfDay _startTime = const TimeOfDay(hour: 6, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 23, minute: 59);

  List<DhikrItem> _adhkarList = [];
  List<String> _blockedPackages = [];
  List> _installedApps = [];

  bool _isLockScreenVisible = false;
  String _currentlyBlockedPkg = "";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initData();
    _setupMethodChannelListener();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  void _setupMethodChannelListener() {
    platform.setMethodCallHandler((call) async {
      if (call.method == "onAppIntercepted") {
        final String pkg = call.arguments as String;
        if (_isWithinSchedule()) {
          setState(() {
            _currentlyBlockedPkg = pkg;
            _isLockScreenVisible = true;
          });
        } else {
          await platform.invokeMethod('unlockAppTemporarily', {'packageName': pkg});
        }
      }
    });
  }

  bool _isWithinSchedule() {
    final now = TimeOfDay.now();
    final nowMins = now.hour * 60 + now.minute;
    final startMins = _startTime.hour * 60 + _startTime.minute;
    final endMins = _endTime.hour * 60 + _endTime.minute;

    if (startMins <= endMins) {
      return nowMins >= startMins && nowMins <= endMins;
    } else {
      return nowMins >= startMins || nowMins <= endMins;
    }
  }

  Future<void> _initData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isBlockerActive = prefs.getBool('isBlockerActive') ?? false;
      _isTimerMode = prefs.getBool('isTimerMode') ?? false;
      _graceMinutes = prefs.getInt('graceMinutes') ?? 15;
      _totalTasbeehCount = prefs.getInt('totalTasbeehCount') ?? 0;
      _interceptedCount = prefs.getInt('interceptedCount') ?? 0;
      _blockedPackages = prefs.getStringList('blockedPackages') ?? [];

      final savedAdhkar = prefs.getString('adhkarList');
      if (savedAdhkar != null) {
        final List decoded = jsonDecode(savedAdhkar);
        _adhkarList = decoded.map((e) => DhikrItem.fromJson(e)).toList();
      } else {
        _adhkarList = [
          DhikrItem(
              id: '1',
              text: 'سُبْحَانَ اللَّهِ وَبِحَمْدِهِ، سُبْحَانَ اللَّهِ الْعَظِيمِ',
              targetCount: 33,
              timerSeconds: 45),
          DhikrItem(
              id: '2',
              text: 'أَسْتَغْفِرُ اللَّهَ الْعَظِيمَ وَأَتُوبُ إِلَيْهِ',
              targetCount: 33,
              timerSeconds: 45),
          DhikrItem(
              id: '3',
              text: 'لَا إِلَهَ إِلَّا أَنْتَ سُبْحَانَكَ إِنِّي كُنْتُ مِنَ الظَّالِمِينَ',
              targetCount: 20,
              timerSeconds: 30),
        ];
      }
    });

    await _checkPermissions();
    await _fetchInstalledApps();
    _syncConfigWithNative();
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isBlockerActive', _isBlockerActive);
    await prefs.setBool('isTimerMode', _isTimerMode);
    await prefs.setInt('graceMinutes', _graceMinutes);
    await prefs.setInt('totalTasbeehCount', _totalTasbeehCount);
    await prefs.setInt('interceptedCount', _interceptedCount);
    await prefs.setStringList('blockedPackages', _blockedPackages);
    await prefs.setString(
        'adhkarList', jsonEncode(_adhkarList.map((e) => e.toJson()).toList()));
    _syncConfigWithNative();
  }

  Future<void> _checkPermissions() async {
    try {
      final Map<dynamic, dynamic> res =
          await platform.invokeMethod('checkPermissions');
      setState(() {
        _hasUsagePermission = res['usage'] ?? false;
        _hasOverlayPermission = res['overlay'] ?? false;
      });
    } catch (_) {}
  }

  Future<void> _fetchInstalledApps() async {
    try {
      final List<dynamic> apps = await platform.invokeMethod('getInstalledApps');
      setState(() {
        _installedApps = apps
            .map((e) => {
                  'name': e['name'].toString(),
                  'package': e['package'].toString(),
                })
            .toList();
      });
    } catch (_) {
      setState(() {
        _installedApps = [
          {'name': 'Instagram', 'package': 'com.instagram.android'},
          {'name': 'TikTok', 'package': 'com.zhiliaoapp.musically'},
          {'name': 'Facebook', 'package': 'com.facebook.katana'},
          {'name': 'YouTube', 'package': 'com.google.android.youtube'},
          {'name': 'X (Twitter)', 'package': 'com.twitter.android'},
        ];
      });
    }
  }

  Future<void> _syncConfigWithNative() async {
    try {
      await platform.invokeMethod('updateBlockerConfig', {
        'blockedApps': _blockedPackages,
        'isActive': _isBlockerActive,
        'graceMinutes': _graceMinutes,
      });
    } catch (_) {}
  }

  void _triggerTestLockScreen() {
    setState(() {
      _currentlyBlockedPkg = "تطبيق تجريبي (معاينة)";
      _isLockScreenVisible = true;
    });
  }

  Future<void> _onUnlockSuccess(int completedTaps) async {
    final pkgToUnlock = _currentlyBlockedPkg;
    setState(() {
      _totalTasbeehCount += completedTaps;
      _interceptedCount += 1;
      _isLockScreenVisible = false;
      _currentlyBlockedPkg = "";
    });
    await _saveData();

    if (pkgToUnlock.isNotEmpty && pkgToUnlock != "تطبيق تجريبي (معاينة)") {
      try {
        await platform.invokeMethod(
            'unlockAppTemporarily', {'packageName': pkgToUnlock});
        SystemNavigator.pop();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLockScreenVisible) {
      return LockOverlayScreen(
        adhkarList: _adhkarList,
        isTimerMode: _isTimerMode,
        blockedAppName: _currentlyBlockedPkg,
        onCompleted: _onUnlockSuccess,
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.shield_moon, color: Color(0xFFD4AF37)),
            SizedBox(width: 10),
            Text('حصن الوقت',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: _triggerTestLockScreen,
            icon: const Icon(Icons.play_circle_fill, color: Color(0xFF10B981)),
            label: const Text('تجربة القفل الآن',
                style: TextStyle(color: Color(0xFF10B981))),
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildDashboardTab(),
          _buildAdhkarManagerTab(),
          _buildAppBlockerTab(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        backgroundColor: const Color(0xFF161B22),
        selectedItemColor: const Color(0xFF10B981),
        unselectedItemColor: Colors.grey,
        onTap: (idx) => setState(() => _currentIndex = idx),
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_rounded), label: 'الرئيسية'),
          BottomNavigationBarItem(
              icon: Icon(Icons.auto_awesome), label: 'تخصيص الأذكار'),
          BottomNavigationBarItem(
              icon: Icon(Icons.app_blocking), label: 'حظر التطبيقات'),
        ],
      ),
    );
  }

  Widget _buildDashboardTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (!_hasUsagePermission || !_hasOverlayPermission)
          _buildPermissionsBanner(),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _isBlockerActive
                  ? [const Color(0xFF064E3B), const Color(0xFF0D1117)]
                  : [const Color(0xFF1F2937), const Color(0xFF161B22)],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _isBlockerActive
                  ? const Color(0xFF10B981)
                  : Colors.grey.shade800,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isBlockerActive ? 'حارس الأذكار مفعل' : 'حارس الأذكار متوقف',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'محظور حالياً: ${_blockedPackages.length} تطبيقات | الوضع: ${_isTimerMode ? "مؤقت زمني" : "عداد تسبيح"}',
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _isBlockerActive,
                activeColor: const Color(0xFF10B981),
                onChanged: (val) {
                  setState(() => _isBlockerActive = val);
                  _saveData();
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildStatCard('إجمالي التسبيحات', '$_totalTasbeehCount',
                  Icons.fingerprint, const Color(0xFF10B981)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard('تشتت تم تحويله لذكر', '$_interceptedCount مرة',
                  Icons.shield_outlined, const Color(0xFFD4AF37)),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('نظام فك القفل المفضل',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _isTimerMode = false);
                        _saveData();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: !_isTimerMode
                              ? const Color(0xFF10B981).withOpacity(0.2)
                              : Colors.transparent,
                          border: Border.all(
                              color: !_isTimerMode
                                  ? const Color(0xFF10B981)
                                  : Colors.grey.shade800),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Column(
                          children: [
                            Icon(Icons.touch_app, color: Color(0xFF10B981)),
                            SizedBox(height: 6),
                            Text('بعدد التسبيحات',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _isTimerMode = true);
                        _saveData();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: _isTimerMode
                              ? const Color(0xFFD4AF37).withOpacity(0.2)
                              : Colors.transparent,
                          border: Border.all(
                              color: _isTimerMode
                                  ? const Color(0xFFD4AF37)
                                  : Colors.grey.shade800),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Column(
                          children: [
                            Icon(Icons.timer, color: Color(0xFFD4AF37)),
                            SizedBox(height: 6),
                            Text('بالمؤقت (التايمر)',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPermissionsBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.12),
        border: Border.all(color: Colors.amber),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('⚠️ صلاحيات مطلوبة لعمل الحظر التلقائي:',
              style:
                  TextStyle(fontWeight: FontWeight.bold, color: Colors.amber)),
          const SizedBox(height: 8),
          if (!_hasUsagePermission)
            ElevatedButton.icon(
              onPressed: () => platform.invokeMethod('requestUsagePermission'),
              icon: const Icon(Icons.bar_chart, size: 18),
              label: const Text('1. تفعيل صلاحية معرفة التطبيق المفتوح'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981)),
            ),
          if (!_hasOverlayPermission)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: ElevatedButton.icon(
                onPressed: () =>
                    platform.invokeMethod('requestOverlayPermission'),
                icon: const Icon(Icons.layers, size: 18),
                label: const Text('2. تفعيل صلاحية الظهور فوق التطبيقات'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD4AF37),
                    foregroundColor: Colors.black),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
      String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 10),
          Text(value,
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildAdhkarManagerTab() {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF10B981),
        onPressed: _showAddDhikrDialog,
        icon: const Icon(Icons.add),
        label: const Text('إضافة ذكر مخصص'),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _adhkarList.length,
        itemBuilder: (context, index) {
          final item = _adhkarList[index];
          return Card(
            color: const Color(0xFF161B22),
            margin: const EdgeInsets.only(bottom: 12),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              contentPadding: const EdgeInsets.all(14),
              title: Text(item.text,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Row(
                  children: [
                    Chip(
                      label: Text('${item.targetCount} تسبيحة',
                          style: const TextStyle(fontSize: 12)),
                      backgroundColor: const Color(0xFF0D1117),
                    ),
                    const SizedBox(width: 8),
                    Chip(
                      label: Text('${item.timerSeconds} ثانية للتايمر',
                          style: const TextStyle(fontSize: 12)),
                      backgroundColor: const Color(0xFF0D1117),
                    ),
                  ],
                ),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                onPressed: () {
                  if (_adhkarList.length > 1) {
                    setState(() => _adhkarList.removeAt(index));
                    _saveData();
                  }
                },
              ),
            ),
          );
        },
      ),
    );
  }

  void _showAddDhikrDialog() {
    final textCtrl = TextEditingController();
    final countCtrl = TextEditingController(text: '33');
    final timerCtrl = TextEditingController(text: '30');

    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF161B22),
          title: const Text('إضافة ذكر جديد'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: textCtrl,
                decoration: const InputDecoration(labelText: 'نص الذكر'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: countCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'عدد مرات التسبيح'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: timerCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'مدة التايمر بالثواني'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981)),
              onPressed: () {
                if (textCtrl.text.trim().isNotEmpty) {
                  setState(() {
                    _adhkarList.add(DhikrItem(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      text: textCtrl.text.trim(),
                      targetCount: int.tryParse(countCtrl.text) ?? 33,
                      timerSeconds: int.tryParse(timerCtrl.text) ?? 30,
                    ));
                  });
                  _saveData();
                  Navigator.pop(context);
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBlockerTab() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: const Color(0xFF161B22),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('وقت تفعيل الحظر:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  TextButton(
                    onPressed: () async {
                      final pickedStart = await showTimePicker(
                          context: context, initialTime: _startTime);
                      if (pickedStart != null) {
                        final pickedEnd = await showTimePicker(
                            context: context, initialTime: _endTime);
                        if (pickedEnd != null) {
                          setState(() {
                            _startTime = pickedStart;
                            _endTime = pickedEnd;
                          });
                        }
                      }
                    },
                    child: Text(
                      'من ${_startTime.format(context)} إلى ${_endTime.format(context)}',
                      style: const TextStyle(color: Color(0xFF10B981)),
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('فترة السماح بعد الذكر:'),
                  DropdownButton<int>(
                    value: _graceMinutes,
                    items: [5, 10, 15, 30, 60]
                        .map((m) =>
                            DropdownMenuItem(value: m, child: Text('$m دقيقة')))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _graceMinutes = val);
                        _saveData();
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _installedApps.length,
            itemBuilder: (context, index) {
              final app = _installedApps[index];
              final pkg = app['package']!;
              final isBlocked = _blockedPackages.contains(pkg);

              return CheckboxListTile(
                activeColor: const Color(0xFF10B981),
                title: Text(app['name']!),
                subtitle: Text(pkg,
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
                value: isBlocked,
                onChanged: (checked) {
                  setState(() {
                    if (checked == true) {
                      _blockedPackages.add(pkg);
                    } else {
                      _blockedPackages.remove(pkg);
                    }
                  });
                  _saveData();
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class LockOverlayScreen extends StatefulWidget {
  final List<DhikrItem> adhkarList;
  final bool isTimerMode;
  final String blockedAppName;
  final Function(int totalTaps) onCompleted;

  const LockOverlayScreen({
    super.key,
    required this.adhkarList,
    required this.isTimerMode,
    required this.blockedAppName,
    required this.onCompleted,
  });

  @override
  State<LockOverlayScreen> createState() => _LockOverlayScreenState();
}

class _LockOverlayScreenState extends State<LockOverlayScreen> {
  int _currentDhikrIndex = 0;
  int _currentCount = 0;
  int _totalSessionTaps = 0;
  int _lastTapTimestamp = 0;
  String _warningMessage = "";

  int _remainingSeconds = 30;
  int _idleSeconds = 0;
  Timer? _timer;

  DhikrItem get _currentDhikr => widget.adhkarList[_currentDhikrIndex];

  @override
  void initState() {
    super.initState();
    if (widget.isTimerMode) {
      _startTimerForCurrentDhikr();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimerForCurrentDhikr() {
    _timer?.cancel();
    _remainingSeconds = _currentDhikr.timerSeconds;
    _idleSeconds = 0;

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _idleSeconds++;
        if (_idleSeconds <= 15) {
          if (_remainingSeconds > 0) {
            _remainingSeconds--;
          } else {
            _moveToNextDhikrOrFinish();
          }
        }
      });
    });
  }

  void _handleUserTap() {
    if (widget.isTimerMode) {
      HapticFeedback.selectionClick();
      setState(() {
        _idleSeconds = 0;
        _totalSessionTaps++;
      });
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastTapTimestamp < 220) {
      setState(() {
        _warningMessage = "تمهل في الذكر ليُكتب لك الأجر كاملًا 🌿";
      });
      return;
    }
    _lastTapTimestamp = now;

    HapticFeedback.lightImpact();
    setState(() {
      _warningMessage = "";
      _currentCount++;
      _totalSessionTaps++;
    });

    if (_currentCount >= _currentDhikr.targetCount) {
      HapticFeedback.heavyImpact();
      _moveToNextDhikrOrFinish();
    }
  }

  void _moveToNextDhikrOrFinish() {
    if (_currentDhikrIndex < widget.adhkarList.length - 1) {
      setState(() {
        _currentDhikrIndex++;
        _currentCount = 0;
      });
      if (widget.isTimerMode) {
        _startTimerForCurrentDhikr();
      }
    } else {
      _timer?.cancel();
      widget.onCompleted(_totalSessionTaps);
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.isTimerMode
        ? (_currentDhikr.timerSeconds - _remainingSeconds) /
            _currentDhikr.timerSeconds
        : _currentCount / _currentDhikr.targetCount;

    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        backgroundColor: const Color(0xFF0D1117),
        body: SafeArea(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _handleUserTap,
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    children: [
                      const Icon(Icons.lock_clock,
                          color: Color(0xFFD4AF37), size: 36),
                      const SizedBox(height: 8),
                      Text(
                        'اذكر الله أولاً قبل فتح (${widget.blockedAppName})',
                        textAlign: TextAlign.center,
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'الذكر ${_currentDhikrIndex + 1} من ${widget.adhkarList.length}',
                        style: const TextStyle(
                            color: Color(0xFF10B981),
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161B22),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: const Color(0xFF10B981).withOpacity(0.4)),
                    ),
                    child: Text(
                      _currentDhikr.text,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 24,
                        height: 1.6,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Column(
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 190,
                            height: 190,
                            child: CircularProgressIndicator(
                              value: progress.clamp(0.0, 1.0),
                              strokeWidth: 10,
                              backgroundColor: Colors.grey.shade800,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                  Color(0xFF10B981)),
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.isTimerMode
                                    ? '$_remainingSeconds ث'
                                    : '$_currentCount / ${_currentDhikr.targetCount}',
                                style: const TextStyle(
                                  fontSize: 34,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFD4AF37),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                widget.isTimerMode
                                    ? (_idleSeconds > 15
                                        ? 'المس الشاشة للمتابعة!'
                                        : 'اقرأ بتأنٍّ...')
                                    : 'اضغط في أي مكان للتسبيح',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: _idleSeconds > 15
                                      ? Colors.amber
                                      : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      if (_warningMessage.isNotEmpty)
                        Text(
                          _warningMessage,
                          style: const TextStyle(
                              color: Colors.amber, fontSize: 13),
                        ),
                    ],
                  ),
                  const Text(
                    '«أَلَا بِذِكْرِ اللَّهِ تَطْمَئِنُّ الْقُلُوبُ»',
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
