// Removes personal detail from captured trajectories before they are shared.
//
//   dart run agent/scrub_trajectories.dart
//
// The trajectories are a required deliverable: they show what each agent did
// and how its tools answered. They also contain whatever the agent read, and
// an early version of the case files carried a phone number that the
// anonymiser missed because it was welded to a narration with no space in
// front of it -- `AirtimeALATMTN07068808118`. The case files are fixed; these
// logs are a record of runs that already happened and cannot be regenerated
// without paying for them again.
//
// Only digit runs are touched. Nothing else is altered, so the reasoning, the
// tool calls and the results a judge needs to follow are all intact.
import 'dart:io';

final _digits = RegExp(r'(?<![0-9])\d{6,}(?![0-9])');

void main() {
  final dir = Directory('agent/trajectories');
  if (!dir.existsSync()) return;
  var files = 0, replaced = 0;
  for (final f in dir.listSync().whereType<File>()) {
    if (!f.path.endsWith('.jsonl')) continue;
    final before = f.readAsStringSync();
    final after = before.replaceAllMapped(_digits, (m) {
      final d = m.group(0)!;
      // Timestamps and token counts are not personal and are worth keeping
      // legible; only long runs that could be an account or a phone number go.
      if (d.length >= 12 && d.startsWith('17')) return d; // epoch millis
      replaced++;
      return List.filled(d.length, '0').join();
    });
    if (after != before) {
      f.writeAsStringSync(after);
      files++;
    }
  }
  stdout.writeln('scrubbed $replaced digit runs across $files trajectories');
}
