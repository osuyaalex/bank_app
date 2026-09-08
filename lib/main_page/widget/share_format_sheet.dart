/// Asks whether the app may send the *shape* of an unreadable bank alert.
///
/// The parser can only learn a format somebody shows it, and the users who
/// have one it cannot read are the ones stuck on a screen telling them so.
/// That is the one moment the request makes sense to both sides.
///
/// The whole design rests on showing them exactly what would be sent. A
/// request to read someone's bank messages is frightening in the abstract and
/// unremarkable once they can see that what leaves the phone is `Amt:###.##`
/// and `<name>`. The preview is not decoration; it is the argument.
library;

import 'package:flutter/material.dart';

import '../../data/bank_topics.dart';
import '../../data/format_reports.dart';
import '../../data/sms_shape.dart';
import 'category_picker.dart' show brandBlue;

const _ink = Color(0xff1C1939);

/// Shows the offer. Returns the report id if something was sent.
Future<String?> showShareFormatSheet(
  BuildContext context, {
  required List<({String sender, String body})> alerts,
  String? appVersion,
}) async {
  final shapes = distinctShapes(alerts);
  if (shapes.isEmpty) return null;

  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (sheetContext) =>
        _ShareFormatSheet(shapes: shapes, appVersion: appVersion),
  );
}

class _ShareFormatSheet extends StatefulWidget {
  const _ShareFormatSheet({required this.shapes, this.appVersion});

  final List<ShapedAlert> shapes;
  final String? appVersion;

  @override
  State<_ShareFormatSheet> createState() => _ShareFormatSheetState();
}

class _ShareFormatSheetState extends State<_ShareFormatSheet> {
  bool _sending = false;
  String? _sentId;
  final _email = TextEditingController();
  bool _emailSaved = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      final id = await FormatReports.submit(
        shapes: widget.shapes,
        appVersion: widget.appVersion,
      );
      // Following the bank, not the user. Nothing about them is stored to do
      // it, and when the format works they are told without us ever having
      // known who they were.
      if (id != null) {
        await BankTopics.followAll(widget.shapes.map((s) => s.sender));
      }
      if (!mounted) return;
      setState(() {
        _sending = false;
        _sentId = id;
      });
    } catch (e) {
      // ignore: avoid_print
      print('FORMAT REPORT: send failed: $e');
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not send. Check your connection.')),
      );
    }
  }

  Future<void> _saveEmail() async {
    final id = _sentId;
    if (id == null) return;
    setState(() => _sending = true);
    try {
      await FormatReports.addEmail(id, _email.text);
      if (!mounted) return;
      setState(() {
        _sending = false;
        _emailSaved = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: height * 0.88),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 6, 22, 6),
                  child: _sentId == null ? _offer() : _thanks(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 18),
                child: _sentId == null ? _offerButtons() : _thanksButtons(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // The offer
  // -------------------------------------------------------------------------

  Widget _offer() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Help us read your bank',
        style: TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w700,
          color: _ink,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        'We can only teach the app a format once we have seen one. '
        'Nothing personal leaves your phone. Every digit and every name '
        'is removed here, before anything is sent.',
        style: TextStyle(
          fontSize: 13.5,
          height: 1.5,
          color: Colors.grey.shade700,
        ),
      ),
      const SizedBox(height: 18),
      Text(
        'THIS IS EXACTLY WHAT WOULD BE SENT',
        style: TextStyle(
          fontSize: 10.5,
          letterSpacing: 0.9,
          fontWeight: FontWeight.w800,
          color: Colors.grey.shade500,
        ),
      ),
      const SizedBox(height: 9),
      for (final shape in widget.shapes) _shapeCard(shape),
      const SizedBox(height: 6),
      Row(
        children: [
          Icon(
            Icons.lock_outline_rounded,
            size: 15,
            color: Colors.grey.shade500,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'No amounts, no balances, no account numbers, no names. '
              'Only the layout.',
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: Colors.grey.shade600,
              ),
            ),
          ),
        ],
      ),
    ],
  );

  Widget _shapeCard(ShapedAlert shaped) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 9),
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: Colors.grey.shade50,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey.shade200),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Which bank wrote it, on the shape itself.
        Text(
          shaped.sender.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w800,
            color: Colors.grey.shade500,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          shaped.shape,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 11.5,
            height: 1.5,
          ),
        ),
      ],
    ),
  );

  Widget _offerButtons() => Row(
    children: [
      Expanded(
        child: TextButton(
          onPressed: _sending ? null : () => Navigator.pop(context),
          style: TextButton.styleFrom(
            foregroundColor: Colors.grey.shade700,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: const Text(
            'No thanks',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        flex: 2,
        child: ElevatedButton(
          onPressed: _sending ? null : _send,
          style: ElevatedButton.styleFrom(
            backgroundColor: brandBlue,
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.grey.shade300,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
            ),
          ),
          child: _sending
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  'Send this',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
        ),
      ),
    ],
  );

  // -------------------------------------------------------------------------
  // Afterwards, and only afterwards, the address
  // -------------------------------------------------------------------------

  Widget _thanks() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: Color(0xff2E7D32),
            size: 22,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Sent. Thank you.',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: _ink,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Text(
        _emailSaved
            ? "We'll write to you when your bank works."
            : 'Want us to tell you when your bank works? Leave an address. '
                  'It is used for that and nothing else.',
        style: TextStyle(
          fontSize: 13.5,
          height: 1.5,
          color: Colors.grey.shade700,
        ),
      ),
      if (!_emailSaved) ...[
        const SizedBox(height: 16),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: InputDecoration(
            hintText: 'you@example.com',
            filled: true,
            fillColor: Colors.grey.shade50,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
    ],
  );

  Widget _thanksButtons() => Row(
    children: [
      Expanded(
        child: TextButton(
          onPressed: _sending ? null : () => Navigator.pop(context, _sentId),
          style: TextButton.styleFrom(
            foregroundColor: Colors.grey.shade700,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: Text(
            _emailSaved ? 'Done' : 'No thanks',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ),
      if (!_emailSaved) ...[
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: ElevatedButton(
            onPressed: _sending || _email.text.trim().isEmpty
                ? null
                : _saveEmail,
            style: ElevatedButton.styleFrom(
              backgroundColor: brandBlue,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey.shade300,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
            ),
            child: const Text(
              'Keep me posted',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ),
        ),
      ],
    ],
  );
}
