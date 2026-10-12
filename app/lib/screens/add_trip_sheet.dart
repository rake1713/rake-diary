import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../format.dart';
import '../shift.dart';
import '../theme.dart';

/// Ставка комиссии парка по умолчанию (в данных задания — 15%).
const defaultCommissionPercent = 15;

/// Случайный id поездки. Создаётся один раз на открытие формы.
String newTripId([Random? random]) {
  final r = random ?? Random.secure();
  final hex = List.generate(
    16,
    (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  return 'm-$hex';
}

/// Быстрый ввод поездки.
///
/// - Время по умолчанию: для сегодняшнего дня — поездка, закончившаяся сейчас.
/// - Комиссия считается сама по ставке парка; её можно поправить вручную.
/// - id создаётся при открытии формы и не меняется при повторных нажатиях
///   «Сохранить». Если ответ потерялся из-за обрыва связи, повторная отправка
///   придёт с тем же id, и сервер вернёт уже сохранённую поездку вместо дубля.
class AddTripSheet extends StatefulWidget {
  const AddTripSheet({
    super.key,
    required this.api,
    required this.date,
    required this.utcOffset,
    this.today,
    this.now,
    this.tripId,
  });

  final ApiClient api;
  final DateTime date;
  final Duration utcOffset;

  /// Сегодняшняя дата водителя; если совпадает с [date], время берётся от «сейчас».
  final DateTime? today;

  /// Текущее время по часам водителя (для тестов).
  final DateTime? now;
  final String? tripId;

  @override
  State<AddTripSheet> createState() => _AddTripSheetState();
}

class _AddTripSheetState extends State<AddTripSheet> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _commission = TextEditingController();
  late final String _id = widget.tripId ?? newTripId();
  late TimeOfDay _start;
  late TimeOfDay _end;
  Payment _payment = Payment.card;
  bool _manualCommission = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = widget.now ?? DateTime.now().toUtc().add(widget.utcOffset);
    final isToday =
        widget.today != null && isoDate(widget.today!) == isoDate(widget.date);
    final nowMin = now.hour * 60 + now.minute;
    if (isToday && nowMin >= 20) {
      _end = TimeOfDay(hour: now.hour, minute: now.minute);
      _start = _fromMinutes(nowMin - 20);
    } else {
      _start = const TimeOfDay(hour: 9, minute: 0);
      _end = const TimeOfDay(hour: 9, minute: 20);
    }
    _amount.addListener(_onAmountChanged);
  }

  @override
  void dispose() {
    _amount.dispose();
    _commission.dispose();
    super.dispose();
  }

  TimeOfDay _fromMinutes(int m) => TimeOfDay(hour: m ~/ 60, minute: m % 60);

  int? get _amountValue => int.tryParse(_amount.text);

  int get _commissionValue => _manualCommission
      ? (int.tryParse(_commission.text) ?? 0)
      : commissionFor(_amountValue ?? 0, percent: defaultCommissionPercent);

  void _onAmountChanged() => setState(() {});

  int get _startMin => _start.hour * 60 + _start.minute;
  int get _endMin => _end.hour * 60 + _end.minute;

  /// Окончание раньше начала по часам — значит, поездка закончилась после полуночи.
  bool get _endsNextDay => _endMin < _startMin;

  int get _durationMin =>
      _endsNextDay ? _endMin + 1440 - _startMin : _endMin - _startMin;

  DateTime _at(TimeOfDay t, {int plusDays = 0}) => DateTime.utc(
    widget.date.year,
    widget.date.month,
    widget.date.day + plusDays,
    t.hour,
    t.minute,
  );

  Future<void> _pick(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _start : _end,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() => isStart ? _start = picked : _end = picked);
  }

  void _editCommission() {
    setState(() {
      _manualCommission = true;
      _commission.text = '$_commissionValue';
    });
  }

  String? _validateAmount(String? v) {
    final n = int.tryParse(v ?? '');
    if (n == null) return 'Введите сумму';
    if (n <= 0) return 'Сумма должна быть больше нуля';
    if (n > 10000000) return 'Слишком большая сумма';
    return null;
  }

  String? _validateCommission(String? v) {
    final n = int.tryParse(v ?? '');
    if (n == null) return 'Введите комиссию (можно 0)';
    if (n < 0) return 'Комиссия не может быть отрицательной';
    final amount = _amountValue;
    if (amount != null && n > amount) return 'Комиссия больше суммы';
    return null;
  }

  Future<void> _save() async {
    if (_busy) return;
    if (_startMin == _endMin) {
      setState(() => _error = 'Окончание должно быть позже начала');
      return;
    }
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final trip = NewTrip(
      id: _id,
      start: _at(_start),
      end: _at(_end, plusDays: _endsNextDay ? 1 : 0),
      amount: _amountValue!,
      payment: _payment,
      commission: _commissionValue,
      utcOffset: widget.utcOffset,
    );
    try {
      await widget.api.addTrip(trip);
      // created и alreadySaved — оба успех: поездка в базе ровно одна.
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() {
        _error = e.isNetwork
            ? '${e.message}. Нажмите «Сохранить» ещё раз — дубля не будет.'
            : e.toString();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = Dash.of(context);
    final digits = [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(8),
    ];
    final amount = _amountValue;
    final net = amount == null ? null : amount - _commissionValue;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Новая поездка',
                style: ui(22, weight: FontWeight.w700, color: d.text),
              ),
              const SizedBox(height: 2),
              Text(formatDayLong(widget.date), style: ui(14, color: d.muted)),
              const SizedBox(height: 18),

              // Сумма — главное поле, крупно.
              TextFormField(
                key: const Key('amount'),
                controller: _amount,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: digits,
                validator: _validateAmount,
                textAlign: TextAlign.left,
                style: figures(40, weight: FontWeight.w700, color: d.text),
                decoration: InputDecoration(
                  hintText: '0',
                  hintStyle: figures(
                    40,
                    weight: FontWeight.w700,
                    color: d.line,
                  ),
                  suffixText: '₸',
                  suffixStyle: figures(
                    28,
                    weight: FontWeight.w600,
                    color: d.muted,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 18,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: _PayButton(
                      key: const Key('pay-card'),
                      label: 'КАРТА',
                      icon: Icons.credit_card_rounded,
                      color: d.card,
                      selected: _payment == Payment.card,
                      onTap: () => setState(() => _payment = Payment.card),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _PayButton(
                      key: const Key('pay-cash'),
                      label: 'НАЛИЧНЫЕ',
                      icon: Icons.payments_outlined,
                      color: d.cash,
                      selected: _payment == Payment.cash,
                      onTap: () => setState(() => _payment = Payment.cash),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: _TimeTile(
                      key: const Key('start-time'),
                      label: 'НАЧАЛО',
                      value: formatTime(_at(_start)),
                      onTap: () => _pick(true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _TimeTile(
                      key: const Key('end-time'),
                      label: _endsNextDay ? 'КОНЕЦ · +1 ДЕНЬ' : 'КОНЕЦ',
                      value: formatTime(_at(_end)),
                      onTap: () => _pick(false),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 4),
                child: Text(
                  _durationMin > 0
                      ? 'в пути ${formatDuration(Duration(minutes: _durationMin))}'
                      : '',
                  style: ui(13, color: d.muted),
                ),
              ),
              const SizedBox(height: 10),

              // Комиссия: по умолчанию по ставке, можно изменить вручную.
              if (_manualCommission)
                TextFormField(
                  key: const Key('commission'),
                  controller: _commission,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: digits,
                  validator: _validateCommission,
                  onChanged: (_) => setState(() {}),
                  style: figures(20, weight: FontWeight.w600, color: d.text),
                  decoration: const InputDecoration(
                    labelText: 'Комиссия',
                    suffixText: '₸',
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 6, 6, 6),
                  decoration: BoxDecoration(
                    color: d.surface2,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Row(
                            children: [
                              Text(
                                'Комиссия $defaultCommissionPercent%',
                                style: ui(15, color: d.muted),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                formatMoney(_commissionValue),
                                key: const Key('commission-auto'),
                                style: figures(
                                  16,
                                  weight: FontWeight.w600,
                                  color: d.text,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      TextButton(
                        key: const Key('commission-edit'),
                        onPressed: _editCommission,
                        child: const Text('Изменить'),
                      ),
                    ],
                  ),
                ),

              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(
                  _error!,
                  key: const Key('form-error'),
                  style: ui(14, color: d.negative),
                ),
              ],
              const SizedBox(height: 18),
              FilledButton(
                key: const Key('save'),
                onPressed: _busy ? null : _save,
                child: _busy
                    ? SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: d.onAccent,
                        ),
                      )
                    : Text(
                        net != null && net >= 0
                            ? 'СОХРАНИТЬ · НА РУКИ ${formatMoney(net)}'
                            : 'СОХРАНИТЬ',
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PayButton extends StatelessWidget {
  const _PayButton({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final d = Dash.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? color.withValues(alpha: 0.16) : d.surface2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected ? color : Colors.transparent,
            width: 2,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: SizedBox(
            height: 56,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: selected ? color : d.muted),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: ui(
                    14,
                    weight: FontWeight.w700,
                    color: selected ? color : d.muted,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TimeTile extends StatelessWidget {
  const _TimeTile({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final d = Dash.of(context);
    return Material(
      color: d.surface2,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: caps(d.muted).copyWith(fontSize: 11)),
              const SizedBox(height: 4),
              Text(
                value,
                style: clock(24, weight: FontWeight.w700, color: d.text),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
