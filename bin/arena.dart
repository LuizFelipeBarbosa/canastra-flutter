/// Runs deterministic, seat-swapped bot comparisons without Flutter or a host.
///
///     dart run bin/arena.dart --profile buraco --players 2 --games 400 \
///       --seed 1 --a hard-legacy --b normal
library;

import 'dart:io';

import 'package:canastra/ai/arena.dart';
import 'package:canastra/engine/profiles.dart';

void main(List<String> args) {
  var profile = 'buraco';
  var players = 2;
  var games = 400;
  var seed = 1;
  var policyA = 'hard-legacy';
  var policyB = 'normal';
  var matches = false;
  var csv = false;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--profile':
        profile = _flagValue(args, ++i, '--profile');
      case '--players':
        players = int.parse(_flagValue(args, ++i, '--players'));
      case '--games':
        games = int.parse(_flagValue(args, ++i, '--games'));
      case '--seed':
        seed = int.parse(_flagValue(args, ++i, '--seed'));
      case '--a':
        policyA = _flagValue(args, ++i, '--a');
      case '--b':
        policyB = _flagValue(args, ++i, '--b');
      case '--matches':
        matches = true;
      case '--csv':
        csv = true;
      case '--help' || '-h':
        stdout.writeln(_usage);
        return;
      default:
        throw FormatException('unknown flag: ${args[i]}\n\n$_usage');
    }
  }

  final spec = ArenaSpec(
    cfg: loadProfile(profile, numPlayers: players),
    games: games,
    baseSeed: seed,
    makeA: agentFactory(policyA),
    makeB: agentFactory(policyB),
    nameA: policyA,
    nameB: policyB,
  );
  final result = matches
      ? runMatchArena(spec, onProgress: _showProgress)
      : runRoundArena(spec, onProgress: _showProgress);

  if (csv) {
    stdout.writeln('seed,normal_diff,swapped_diff,paired_diff');
    for (final observation in result.observations) {
      stdout.writeln(
        '${observation.seed},${observation.normalDiff},'
        '${observation.swappedDiff},'
        '${observation.pairedDiff.toStringAsFixed(1)}',
      );
    }
  } else {
    stdout.writeln(result.format());
  }
}

String _flagValue(List<String> args, int index, String flag) {
  if (index >= args.length || args[index].startsWith('--')) {
    throw FormatException('$flag requires a value');
  }
  return args[index];
}

void _showProgress(int done, int total) {
  final interval = total < 10 ? 1 : total ~/ 10;
  if (done == total || done % interval == 0) {
    stderr.writeln('Completed $done/$total pairs');
  }
}

const _usage = '''Usage: dart run bin/arena.dart [options]

  --profile NAME   rules profile (default: buraco)
  --players N      seats, normally 2 or 4 (default: 2)
  --games N        paired seed observations (default: 400)
  --seed N         first game seed (default: 1)
  --a POLICY       policy A: easy, normal, hard-legacy, hard
  --b POLICY       policy B: easy, normal, hard-legacy, hard
  --matches        play full matches instead of single rounds
  --csv            emit one CSV row per paired observation''';
