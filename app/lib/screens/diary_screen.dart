import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../format.dart';
import '../shift.dart';
import '../theme.dart';
import '../widgets/hero_summary.dart';
import '../widgets/shift_timeline.dart';
import '../widgets/week_strip.dart';
import 'add_trip_sheet.dart';

const _weekdaysShort = ['ПН', 'ВТ', 'СР', 'ЧТ', 'ПТ', 'СБ', 'ВС'];

class DiaryScreen extends StatefulWidget {
  const DiaryScreen({
    super.key,
    required this.api,
    required this.driver,
    required this.onLogout,
    required this.onSessionExpired,
  });

  final ApiClient api;
  final Driver driver;
  final VoidCallback onLogout;
  final VoidCallback onSessionExpired;

  @override
  State<DiaryScreen> createState() => _DiaryScreenState();
}

class _DiaryScreenState extends State<DiaryScreen> {
  /// Выбранный день (календарная дата водителя, объект в UTC).
  late DateTime _date;
  Day? _day;
  ApiException? _error;
  bool _loading = true;

  /// «На руки» по дням загруженной недели.
  Map<String, int> _weekNet = const {};
  String? _loadedWeek;

  /// Направление последнего переключения: для анимации влево/вправо.
  int _direction = 0;

  /// Защита от гонки: ответ на старый запрос не должен затереть новый день.
  int _requestSeq = 0;

  DateTime get _today {
    final now = DateTime.now().toUtc().add(widget.driver.utcOffset);
    return DateTime.utc(now.year, now.month, now.day);
  }

  @override
  void initState() {
    super.initState();
    _date = _today;
    _init();
  }

  Future<void> _init() async {
    try {
      final days = await widget.api.days();
      // Открываем последний день с поездками — так сразу видно данные.
      if (days.isNotEmpty) _date = parseIsoDate(days.first.date);
    } on ApiException catch (e) {
      if (_handleAuth(e)) return;
    }
    await Future.wait([_load(), _loadWeek()]);
  }

  bool _handleAuth(ApiException e) {
    if (e.isUnauthorized) {
      widget.onSessionExpired();
      return true;
    }
    return false;
  }

  Future<void> _load() async {
    final seq = ++_requestSeq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final day = await widget.api.day(isoDate(_date));
      if (!mounted || seq != _requestSeq) return;
      setState(() => _day = day);
    } on ApiException catch (e) {
      if (!mounted || seq != _requestSeq || _handleAuth(e)) return;
      setState(() => _error = e);
    } finally {
      if (mounted && seq == _requestSeq) setState(() => _loading = false);
    }
  }

  Future<void> _loadWeek({bool force = false}) async {
    final monday = weekStart(_date);
    final key = isoDate(monday);
    if (!force && key == _loadedWeek) return;
    try {
      final days = await widget.api.days(
        from: key,
        to: isoDate(monday.add(const Duration(days: 6))),
      );
      if (!mounted || isoDate(weekStart(_date)) != key) return;
      setState(() {
        _loadedWeek = key;
        _weekNet = {for (final d in days) d.date: d.net};
      });
    } on ApiException catch (e) {
      _handleAuth(e);
    }
  }

  void _go(DateTime d) {
    if (isoDate(d) == isoDate(_date)) return;
    HapticFeedback.selectionClick();
    setState(() {
      _direction = d.isAfter(_date) ? 1 : -1;
      _date = d;
    });
    _load();
    _loadWeek();
  }

  void _shift(int days) => _go(_date.add(Duration(days: days)));

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.utc(2020),
      lastDate: _today.add(const Duration(days: 1)),
    );
    if (picked != null) {
      _go(DateTime.utc(picked.year, picked.month, picked.day));
    }
  }

  Future<void> _addTrip() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      // На широком экране форма не растягивается на весь монитор.
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => AddTripSheet(
        api: widget.api,
        date: _date,
        today: _today,
        utcOffset: widget.driver.utcOffset,
      ),
    );
    if (saved == true && mounted) {
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Поездка сохранена')));
      await Future.wait([_load(), _loadWeek(force: true)]);
    }
  }

  void _onSwipe(DragEndDetails details) {
    final v = details.primaryVelocity ?? 0;
    if (v.abs() < 300) return;
    _shift(v < 0 ? 1 : -1);
  }

  @override
  Widget build(BuildContext context) {
    final d = Dash.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth >= wideBreakpoint
          ? _wideLayout(d)
          : _narrowLayout(d),
    );
  }

  /// Телефон: одна колонка, большая кнопка внизу под большой палец.
  Widget _narrowLayout(Dash d) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              children: [
                _header(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: _weekStrip(),
                ),
                const SizedBox(height: 8),
                _progress(d),
                Expanded(child: _swipeable(_animated(_singleColumn(d)))),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: _addButton(),
            ),
          ),
        ),
      ),
    );
  }

  /// Широкий экран (веб на компьютере, планшет): слева день и неделя,
  /// справа лента смены; кнопка добавления — в шапке.
  Widget _wideLayout(Dash d) {
    final day = _day;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: _sidePanelWidth,
                          child: _header(showProfile: false),
                        ),
                        const Spacer(),
                        _addButton(compact: true),
                        const SizedBox(width: 8),
                        _ProfileMenu(
                          driverName: widget.driver.name,
                          onLogout: widget.onLogout,
                        ),
                      ],
                    ),
                  ),
                  _progress(d),
                  Expanded(
                    child: _swipeable(
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: _sidePanelWidth,
                            child: ListView(
                              padding: const EdgeInsets.only(
                                top: 8,
                                bottom: 24,
                              ),
                              children: [
                                _weekStrip(),
                                const SizedBox(height: 16),
                                _animated(
                                  day == null
                                      ? (_stateMessage(d) ??
                                            const SizedBox.shrink())
                                      : HeroSummary(
                                          summary: day.summary,
                                          shift: ShiftStats.of(
                                            day.trips,
                                            day.summary.net,
                                          ),
                                        ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 32),
                          Expanded(
                            child: _animated(
                              day == null
                                  ? const SizedBox.shrink()
                                  : ListView(
                                      padding: const EdgeInsets.only(
                                        top: 12,
                                        bottom: 24,
                                      ),
                                      children: _tripsSection(d, day),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static const _sidePanelWidth = 440.0;

  Widget _header({bool showProfile = true}) => _Header(
    date: _date,
    isToday: isoDate(_date) == isoDate(_today),
    driverName: widget.driver.name,
    onPrev: () => _shift(-1),
    onNext: () => _shift(1),
    onPick: _pickDate,
    onLogout: widget.onLogout,
    showProfile: showProfile,
  );

  Widget _weekStrip() => WeekStrip(
    selected: _date,
    today: _today,
    netByDate: _weekNet,
    onSelect: _go,
  );

  Widget _progress(Dash d) => _loading && _day != null
      ? LinearProgressIndicator(minHeight: 2, backgroundColor: d.bg)
      : const SizedBox(height: 2);

  Widget _addButton({bool compact = false}) => FilledButton.icon(
    key: const Key('add-trip'),
    onPressed: _addTrip,
    style: compact
        ? FilledButton.styleFrom(
            minimumSize: const Size(0, 52),
            padding: const EdgeInsets.symmetric(horizontal: 24),
          )
        : null,
    icon: const Icon(Icons.add_rounded, size: 26),
    label: const Text('ПОЕЗДКА'),
  );

  Widget _swipeable(Widget child) => GestureDetector(
    onHorizontalDragEnd: _onSwipe,
    behavior: HitTestBehavior.translucent,
    child: child,
  );

  /// Смена дня — короткий сдвиг с затуханием в сторону переключения.
  Widget _animated(Widget child) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 220),
    transitionBuilder: (child, animation) => FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween(
          begin: Offset(0.06 * _direction, 0),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    ),
    child: KeyedSubtree(
      key: ValueKey(_day?.date ?? 'loading-${isoDate(_date)}'),
      child: child,
    ),
  );

  /// Ошибка или загрузка, пока данных дня нет. null — данные есть.
  Widget? _stateMessage(Dash d) {
    if (_day != null) return null;
    if (_error != null) {
      return _Message(
        icon: Icons.cloud_off_rounded,
        text: _error!.message,
        action: TextButton(onPressed: _load, child: const Text('Повторить')),
      );
    }
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 48),
      child: Center(child: CircularProgressIndicator()),
    );
  }

  List<Widget> _tripsSection(Dash d, Day day) {
    if (day.trips.isEmpty) {
      return const [
        _Message(
          icon: Icons.local_taxi_outlined,
          text: 'В этот день поездок нет',
        ),
      ];
    }
    return [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 10),
        child: Text(
          'СМЕНА · ${pluralTrips(day.trips.length).toUpperCase()}',
          style: caps(d.muted),
        ),
      ),
      ShiftTimeline(trips: day.trips),
    ];
  }

  Widget _singleColumn(Dash d) {
    final day = _day;
    if (day == null) return _stateMessage(d)!;
    return RefreshIndicator(
      color: d.accent,
      backgroundColor: d.surface,
      onRefresh: () => Future.wait([_load(), _loadWeek(force: true)]),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          HeroSummary(
            summary: day.summary,
            shift: ShiftStats.of(day.trips, day.summary.net),
          ),
          const SizedBox(height: 22),
          ..._tripsSection(d, day),
        ],
      ),
    );
  }
}

/// С какой ширины экран делится на две колонки.
const wideBreakpoint = 900.0;

class _Header extends StatelessWidget {
  const _Header({
    required this.date,
    required this.isToday,
    required this.driverName,
    required this.onPrev,
    required this.onNext,
    required this.onPick,
    required this.onLogout,
    this.showProfile = true,
  });

  final bool showProfile;
  final DateTime date;
  final bool isToday;
  final String driverName;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onPick;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final d = Dash.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Предыдущий день',
            icon: const Icon(Icons.chevron_left_rounded, size: 30),
            onPressed: onPrev,
          ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onPick,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    Text(
                      '${_weekdaysShort[date.weekday - 1]} ${formatDayNumeric(date).substring(0, 5)}',
                      key: const Key('day-title'),
                      style: clock(22, weight: FontWeight.w700, color: d.text),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isToday ? 'сегодня' : formatDayMonth(date),
                      style: ui(13, color: isToday ? d.accentText : d.muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Следующий день',
            icon: const Icon(Icons.chevron_right_rounded, size: 30),
            onPressed: onNext,
          ),
          if (showProfile)
            _ProfileMenu(driverName: driverName, onLogout: onLogout),
        ],
      ),
    );
  }
}

class _ProfileMenu extends StatelessWidget {
  const _ProfileMenu({required this.driverName, required this.onLogout});

  final String driverName;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final d = Dash.of(context);
    return PopupMenuButton<void>(
      tooltip: 'Профиль',
      icon: Icon(Icons.account_circle_outlined, color: d.muted),
      color: d.surface2,
      itemBuilder: (_) => [
        PopupMenuItem(
          enabled: false,
          child: Text(driverName, style: ui(14, color: d.muted)),
        ),
        PopupMenuItem(
          onTap: onLogout,
          child: Row(
            children: [
              Icon(Icons.logout_rounded, size: 20, color: d.text),
              const SizedBox(width: 10),
              Text('Выйти', style: ui(15, color: d.text)),
            ],
          ),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final d = Dash.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 44, color: d.line),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: ui(15, color: d.muted),
          ),
          ?action,
        ],
      ),
    );
  }
}
