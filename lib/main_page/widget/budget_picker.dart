import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../data/budget_suggestion.dart';
import '../../story/story_day.dart';

const _brand = Color(0xff2E5BFF);
const _ink = Color(0xff1C1939);

/// Picking a monthly budget without typing one.
///
/// Typing is the slowest thing this app asks of anybody, and it asks for it at
/// the worst moment -- before the user has seen a single thing the app can do.
/// So the keyboard is no longer the way in. The figure is shown large with a
/// nudge either side, and underneath it are the amounts worth choosing:
/// drawn from the user's own months where the app has them, and a ladder of
/// round numbers where it does not.
///
/// Typing is still there, one tap away, because somebody will want ₦17,500
/// exactly and refusing them that would be its own kind of rude.
class BudgetPicker extends StatefulWidget {
  const BudgetPicker({
    super.key,
    required this.initial,
    required this.currency,
    required this.onChanged,
    this.history = const [],
  });

  final double initial;
  final String currency;
  final ValueChanged<double> onChanged;

  /// What this category cost per month, if the app knows. Two or more real
  /// months turns the choices from generic round numbers into the user's own
  /// spending.
  final List<double> history;

  @override
  State<BudgetPicker> createState() => _BudgetPickerState();
}

class _BudgetPickerState extends State<BudgetPicker> {
  late double _value = widget.initial;
  late final TextEditingController _typed =
      TextEditingController(text: _value > 0 ? _fmt.format(_value) : '');
  bool _typing = false;

  /// The ladder opens near the figure already chosen. Starting at ₦1,000 when
  /// the budget is ₦400,000 means scrolling past nine chips to find anything
  /// useful, which is the work this row exists to remove.
  late final ScrollController _ladder =
      ScrollController(initialScrollOffset: _ladderOffset());

  double _ladderOffset() {
    final at = budgetLadder.indexWhere((v) => v >= _value);
    if (at <= 1) return 0;
    return (at - 1) * 78.0;
  }

  static final _fmt = NumberFormat('#,###');

  ({double tight, double usual, double roomy})? get _choices =>
      Story.budgetsFromHistory ? budgetChoices(widget.history) : null;

  @override
  void dispose() {
    _typed.dispose();
    _ladder.dispose();
    super.dispose();
  }

  void _set(double v) {
    final next = v < 0 ? 0.0 : v;
    setState(() => _value = next);
    _typed.text = next > 0 ? _fmt.format(next) : '';
    widget.onChanged(next);
  }

  void _nudge(int direction) {
    // Stepped from the figure it is about to become, so crossing a threshold
    // does not leave the user stepping by the old scale.
    final step = budgetStep(_value <= 0 ? 1000 : _value);
    HapticFeedback.selectionClick();
    _set(_value + step * direction);
  }

  @override
  Widget build(BuildContext context) {
    final c = _choices;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xffF7F8FC),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              _NudgeButton(
                icon: Icons.remove_rounded,
                enabled: _value > 0,
                onTap: () => _nudge(-1),
              ),
              Expanded(
                child: _typing
                    ? TextField(
                        controller: _typed,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        inputFormatters: [_ThousandsFormatter()],
                        style: const TextStyle(
                            fontSize: 27,
                            fontWeight: FontWeight.w700,
                            color: _ink),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          prefixText: widget.currency,
                          prefixStyle: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey.shade500),
                        ),
                        onChanged: (raw) {
                          final v = double.tryParse(
                                  raw.replaceAll(RegExp(r'[^0-9]'), '')) ??
                              0;
                          setState(() => _value = v);
                          widget.onChanged(v);
                        },
                      )
                    : GestureDetector(
                        onTap: () => setState(() => _typing = true),
                        behavior: HitTestBehavior.opaque,
                        child: Center(
                          child: Text(
                            '${widget.currency}${_fmt.format(_value)}',
                            style: TextStyle(
                              fontSize: 27,
                              fontWeight: FontWeight.w700,
                              color: _value > 0 ? _ink : Colors.grey.shade400,
                            ),
                          ),
                        ),
                      ),
              ),
              _NudgeButton(
                icon: Icons.add_rounded,
                enabled: true,
                onTap: () => _nudge(1),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        if (c != null) ...[
          _sectionLabel('FROM WHAT YOU ACTUALLY SPEND'),
          const SizedBox(height: 8),
          Row(
            children: [
              _Choice(
                  label: 'Tight',
                  amount: c.tight,
                  currency: widget.currency,
                  selected: _value == c.tight,
                  onTap: () => _set(c.tight)),
              const SizedBox(width: 8),
              _Choice(
                  label: 'Usual',
                  amount: c.usual,
                  currency: widget.currency,
                  selected: _value == c.usual,
                  onTap: () => _set(c.usual)),
              const SizedBox(width: 8),
              _Choice(
                  label: 'Roomy',
                  amount: c.roomy,
                  currency: widget.currency,
                  selected: _value == c.roomy,
                  onTap: () => _set(c.roomy)),
            ],
          ),
          const SizedBox(height: 16),
        ],

        // Always offered, history or not. The three figures above are what the
        // user has been spending; this is what they might want to spend, which
        // is a different question and often the one they came to answer.
        _sectionLabel(c != null ? 'OR PICK AN AMOUNT' : 'COMMON AMOUNTS'),
        const SizedBox(height: 8),
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            controller: _ladder,
            padding: EdgeInsets.zero,
            itemCount: budgetLadder.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => _Pill(
              text: compactMoney(budgetLadder[i], widget.currency),
              selected: _value == budgetLadder[i],
              onTap: () => _set(budgetLadder[i]),
            ),
          ),
        ),

        if (!_typing) ...[
          const SizedBox(height: 6),
          TextButton(
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 34),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: Colors.grey.shade600,
            ),
            onPressed: () => setState(() => _typing = true),
            child: const Text('Enter an exact amount',
                style: TextStyle(fontSize: 12.5)),
          ),
        ],
      ],
    );
  }
}

Widget _sectionLabel(String text) => Builder(
      builder: (_) => Text(
        text,
        style: TextStyle(
            fontSize: 10.5,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade500),
      ),
    );

class _NudgeButton extends StatelessWidget {
  const _NudgeButton(
      {required this.icon, required this.enabled, required this.onTap});

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey.shade300),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: 46,
            height: 46,
            child: Icon(icon,
                size: 22,
                color: enabled ? _ink : Colors.grey.shade300),
          ),
        ),
      );
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.amount,
    required this.currency,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final double amount;
  final String currency;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            decoration: BoxDecoration(
              color: selected ? const Color(0xffF0F4FF) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? _brand : Colors.grey.shade300,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Column(
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: selected ? _brand : Colors.grey.shade600)),
                const SizedBox(height: 3),
                FittedBox(
                  child: Text(
                    compactMoney(amount, currency),
                    style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: selected ? _brand : _ink),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _Pill extends StatelessWidget {
  const _Pill(
      {required this.text, required this.selected, required this.onTap});

  final String text;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? const Color(0xffF0F4FF) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? _brand : Colors.grey.shade300,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Text(text,
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: selected ? _brand : _ink)),
        ),
      );
}

/// Groups digits as they are typed, for the rare exact figure.
class _ThousandsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const TextEditingValue();
    final n = int.tryParse(digits);
    if (n == null) return oldValue;
    final text = NumberFormat('#,###').format(n);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
