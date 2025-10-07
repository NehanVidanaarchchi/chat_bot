import 'dart:math';

enum RiskTier { low, moderate, high }

class HeartBotService {
  // ===== Public, chat-friendly API =====

  /// Call this when your chat app starts.
  String greeting() =>
      "Hi! Tell me your risk % and I’ll suggest next steps.\n"
          "You can say: risk=23%  or  23%  (also supports risk=low/moderate/high).\n"
          "Example: risk=22%, age=60, bp=150, chol=240";

  /// One-shot helper that accepts either a percentage (preferred) or a textual tier.
  /// - If the message includes a % (e.g., `risk=23%`, `23%`, `risk 23`), I’ll map it to a tier.
  /// - Else if it includes a tier (`risk=high`, `high risk`), I’ll use that.
  /// - Otherwise, I’ll ask for a % or tier.
  ///
  /// You can optionally pass priorInputs to tailor tips, but if you just send a percentage,
  /// I’ll use generic tips for that tier.
  String handleUserMessage(String userText, {Map<String, dynamic>? priorInputs}) {
    final percent = _parseRiskPercentFromText(userText);
    if (percent != null) {
      final tier = _tierFromPercent(percent);
      final inline = _parseInputs(userText);
      final merged = {
        if (priorInputs != null) ...priorInputs,
        if (inline.isNotEmpty) ...inline,
      };
      return reportForPercent(riskPercent: percent, inputs: merged.isEmpty ? null : merged);
    }

    final risk = _parseRiskFromText(userText);
    if (risk == null) {
      return "Which risk should I use?\n"
          "Send a percentage like: 7%  or  risk=23%\n"
          "Or send a tier like: risk=low, risk=moderate, risk=high.\n"
          "Optionally add values (e.g., age=58, bp=142, chol=238).";
    }

    // Try to pull any inline inputs from this message and merge with prior ones
    final inline = _parseInputs(userText);
    final merged = {
      if (priorInputs != null) ...priorInputs,
      if (inline.isNotEmpty) ...inline,
    };
    return reportForRisk(risk: risk, inputs: merged.isEmpty ? null : merged);
  }

  /// New: main entry if you prefer sending a *percentage*.
  /// Example: reportForPercent(riskPercent: 22.5)
  String reportForPercent({
    required double riskPercent,
    Map<String, dynamic>? inputs,
  }) {
    final double p = riskPercent.clamp(0, 100).toDouble();
    final tier = _tierFromPercent(p);
    final tips = (inputs == null || inputs.isEmpty)
        ? _genericActionsForTier(tier)
        : _actionsForTier(tier, inputs);

    final bullets = tips.take(6).map((t) => "• $t").join("\n");

// Show percentage with no decimals if integer, else 1 decimal
    final pctText = p % 1 == 0 ? p.toStringAsFixed(0) : p.toStringAsFixed(1);

    return "Risk: ${_tierLabel(tier)} ($pctText%)\nNext:\n$bullets";}

  /// Legacy/Text tier entry—still supported.
  String reportForRisk({
    required String risk,
    Map<String, dynamic>? inputs,
  }) {
    final tier = _parseRisk(risk);
    if (tier == null) {
      return "Risk: Unknown\nNext:\n• Please provide a valid risk: percentage (e.g., 12%) or Low / Moderate / High.";
    }
    return reportForRiskTier(tier: tier, inputs: inputs);
  }

  /// Variant that accepts the enum directly.
  String reportForRiskTier({
    required RiskTier tier,
    Map<String, dynamic>? inputs,
  }) {
    final tips = (inputs == null || inputs.isEmpty)
        ? _genericActionsForTier(tier)
        : _actionsForTier(tier, inputs);

    final bullets = tips.take(6).map((t) => "• $t").join("\n");
    return "Risk: ${_tierLabel(tier)}\nNext:\n$bullets";
  }

  // ===== Helpers: parsing risk % / risk tier & optional inputs =====

  /// Extract a risk tier string from user text.
  /// Supports: `risk=high|moderate|medium|low`, “high risk”, “risk high”, etc.
  String? _parseRiskFromText(String input) {
    final lower = input.toLowerCase();

    // 1) risk=<value>
    final m = RegExp(r'\brisk\s*=\s*(high|moderate|medium|low)\b').firstMatch(lower);
    if (m != null) {
      final v = m.group(1)!;
      return v == 'medium' ? 'moderate' : v;
    }

    // 2) phrases
    if (RegExp(r'\bhigh\s+risk\b|\brisk\s+high\b').hasMatch(lower)) return 'high';
    if (RegExp(r'\b(moderate|medium)\s+risk\b|\brisk\s+(moderate|medium)\b').hasMatch(lower)) return 'moderate';
    if (RegExp(r'\blow\s+risk\b|\brisk\s+low\b').hasMatch(lower)) return 'low';

    return null;
  }

  /// Extract a risk percentage from user text.
  /// Accepts: `risk=23%`, `risk=23`, `23%`, `risk 7.5%`, etc.
  double? _parseRiskPercentFromText(String input) {
    final lower = input.toLowerCase();

    // direct % anywhere (e.g., "7.5%")
    final withPct = RegExp(r'(\d+(\.\d+)?)\s*%').firstMatch(lower);
    if (withPct != null) {
      final raw = withPct.group(1);
      final v = double.tryParse(raw ?? '');
      if (v != null) return v;
    }

    // risk=<number> (assume %)
    final afterEq = RegExp(r'\brisk\s*=\s*(\d+(\.\d+)?)\b').firstMatch(lower);
    if (afterEq != null) {
      final raw = afterEq.group(1);
      final v = double.tryParse(raw ?? '');
      if (v != null) return v;
    }

    // "risk 12.3"
    final spaced = RegExp(r'\brisk\s+(\d+(\.\d+)?)\b').firstMatch(lower);
    if (spaced != null) {
      final raw = spaced.group(1);
      final v = double.tryParse(raw ?? '');
      if (v != null) return v;
    }

    // lone number (only if message looks like just a number)
    final justNum = RegExp(r'^\s*(\d+(\.\d+)?)\s*$').firstMatch(lower);
    if (justNum != null) {
      final raw = justNum.group(1);
      final v = double.tryParse(raw ?? '');
      if (v != null) return v;
    }

    return null;
  }

  /// Parse optional inputs from "key=value" in user text.
  /// Aliases: gender→sex, bp/sbp/restingbp→trestbps, cholesterol/tc→chol,
  /// hr/maxhr/heart_rate/heartrate→thalach, glucose→fbs (>120 → 1 else 0).
  Map<String, dynamic> _parseInputs(String input) {
    final lower = input.toLowerCase();
    final parts = lower
        .replaceAll('\n', ' ')
        .split(RegExp(r'[,\s]+'))
        .where((s) => s.contains('='))
        .toList();

    final Map<String, dynamic> out = {};

    num? toNum(String s) {
      final clean = s.replaceAll(RegExp(r'[^0-9\.\-]'), '');
      if (clean.isEmpty) return null;
      if (clean.contains('.')) return double.tryParse(clean);
      return int.tryParse(clean);
    }

    String canonical(String k) {
      k = k.trim();
      if (k == 'gender') return 'sex';
      if (k == 'bp' || k == 'sbp' || k == 'restingbp') return 'trestbps';
      if (k == 'cholesterol' || k == 'tc') return 'chol';
      if (k == 'hr' || k == 'maxhr' || k == 'heart_rate' || k == 'heartrate') return 'thalach';
      if (k == 'glucose') return 'glucose';
      return k;
    }

    for (final p in parts) {
      final idx = p.indexOf('=');
      if (idx <= 0) continue;
      var key = canonical(p.substring(0, idx).trim());
      final val = p.substring(idx + 1).trim();

      final n = toNum(val);
      if (n == null) continue;

      if (key == 'oldpeak') {
        out['oldpeak'] = (n is num) ? n.toDouble() : 0.0;
        continue;
      }
      if (key == 'glucose') {
        final g = (n is num) ? n.toDouble() : 0.0;
        out['fbs'] = g > 120 ? 1 : 0;
        continue;
      }
      out[key] = (n is num) ? n.round() : 0;
    }

    return out;
  }

  // ===== Internal helpers =====

  /// Map a percentage to a tier.
  /// Defaults:
  ///   Low:       < 5%
  ///   Moderate:  5% – 19.9%
  ///   High:      ≥ 20%
  RiskTier _tierFromPercent(double percent) {
    if (percent >= 20.0) return RiskTier.high;
    if (percent >= 5.0) return RiskTier.moderate;
    return RiskTier.low;
  }

  RiskTier? _parseRisk(String s) {
    final x = s.trim().toLowerCase();
    if (x.startsWith('h') || x.contains('severe')) return RiskTier.high;
    if (x.startsWith('m') || x.contains('medium')) return RiskTier.moderate;
    if (x.startsWith('l') || x.contains('mild')) return RiskTier.low;
    return null;
  }

  String _tierLabel(RiskTier t) {
    switch (t) {
      case RiskTier.high:
        return "High";
      case RiskTier.moderate:
        return "Moderate";
      case RiskTier.low:
        return "Low";
    }
  }

  List<String> _actionsForTier(RiskTier tier, Map<String, dynamic> p) {
    final tips = <String>[];

    int i(String k) {
      final v = p[k];
      if (v is int) return v;
      if (v is double) return v.round();
      return int.tryParse("${v ?? 0}") ?? 0;
    }

    double d(String k) {
      final v = p[k];
      if (v is num) return v.toDouble();
      return double.tryParse("${v ?? 0}") ?? 0.0;
    }

    final age = i("age");
    final sex = i("sex");
    final trestbps = i("trestbps");
    final chol = i("chol");
    final fbs = i("fbs");
    final exang = i("exang");
    final cp = i("cp");
    final restecg = i("restecg");
    final oldpeak = d("oldpeak");
    final slope = i("slope");
    final thalach = i("thalach");

    // Tier headline
    switch (tier) {
      case RiskTier.high:
        tips.add("Book a cardiology visit soon (ECG/echo ± stress test). If chest pain is severe or you’re breathless, seek urgent care.");
        break;
      case RiskTier.moderate:
        tips.add("Arrange a clinician review to plan prevention, meds if needed, and follow-up.");
        break;
      case RiskTier.low:
        tips.add("Keep healthy habits and recheck basic metrics periodically.");
        break;
    }

    // Targeted nudges
    if (trestbps >= 140) {
      tips.add("Blood pressure is high—keep a home BP log and discuss treatment.");
    } else if (trestbps >= 130) {
      tips.add("BP borderline—aim <130/80 with salt reduction and activity.");
    }

    if (chol >= 240) {
      tips.add("Cholesterol ≥240—ask about a full lipid panel and statin options.");
    } else if (chol >= 200) {
      tips.add("Cholesterol borderline—optimize diet; recheck in 3–6 months.");
    }

    if (fbs == 1) tips.add("Fasting sugar >120—consider HbA1c testing and a glucose plan.");

    if (exang == 1) tips.add("Chest pain on exertion—pause strenuous exercise; consider a supervised stress test.");
    if (cp > 0) tips.add("Log chest-pain triggers/duration and share with your clinician.");

    if (restecg >= 1 || oldpeak >= 2.0 || slope == 2) {
      tips.add("ECG/ST changes—have a clinician interpret to rule out ischemia.");
    }

    // Functional capacity vs age
    final predictedMax = max(120, 220 - age);
    if (thalach > 0 && thalach < 0.7 * predictedMax) {
      tips.add("Max heart rate lower than expected—ask about a supervised exercise test.");
    }

    // Age-aware reminder
    if ((sex == 1 && age >= 55) || (sex == 0 && age >= 65)) {
      tips.add("Age increases baseline risk—focus on BP, lipids, glucose, and activity.");
    }

    // Universal one-liner
    tips.add("Core habits: 150 min/week activity, more plants/fiber, less salt/alcohol, no smoking.");

    // De-dup keep order
    final seen = <String>{};
    final uniq = <String>[];
    for (final t in tips) {
      if (seen.add(t)) uniq.add(t);
    }
    return uniq;
  }

  List<String> _genericActionsForTier(RiskTier tier) {
    switch (tier) {
      case RiskTier.high:
        return [
          "Book a cardiology visit soon (ECG/echo ± stress test).",
          "If symptoms are severe (crushing chest pain, breathless, faint), seek urgent care.",
          "Start lifestyle changes now: activity, diet, stop smoking.",
          "Track BP, cholesterol, and glucose; address any high values.",
        ];
      case RiskTier.moderate:
        return [
          "Schedule a clinician review to plan prevention and monitoring.",
          "Track BP, lipids, and glucose; improve diet and activity.",
          "Build consistent exercise (≥150 min/week) and sleep routine.",
        ];
      case RiskTier.low:
        return [
          "Maintain healthy habits; recheck BP/lipids/glucose periodically.",
          "Know warning signs (new/worsening chest pain, breathlessness).",
          "Keep active and prioritize a plant-forward diet; avoid smoking.",
        ];
    }
  }
}
