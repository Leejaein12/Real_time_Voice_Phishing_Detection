import '../models/analysis_result.dart';

class PhishingDetector {
  static const _highRiskPhrases = [
    '금융감독원', '검찰청', '경찰청', '국세청', '금감원',
    '수사관', '검사님', '형사님',
    '계좌이체', '계좌 이체',
    '명의도용', '명의 도용',
    '보안계좌', '안전계좌', '임시계좌',
    '대출사기', '범죄연루', '범죄에 연루',
    '비밀번호 알려', '주민번호 알려', '개인정보 알려',
    '지금 바로 이체', '즉시 이체', '빨리 송금',
  ];

  static const _keywords = [
    '계좌', '이체', '송금', '입금', '출금',
    '비밀번호', '주민번호', '공인인증', 'otp',
    '검사', '경찰', '수사', '체포', '압수', '영장', '구속',
    '대출', '저금리', '한도', '승인', '대환',
    '환급', '세금', '과태료', '벌금', '납부',
    '명의', '도용', '사기', '범죄', '피해', '피해자',
    '보안', '인증', '카드', '계정',
    '긴급', '즉시', '바로', '빨리', '당장',
  ];

  AnalysisResult analyze(String text, String windowText) {
    if (text.isEmpty) {
      return AnalysisResult(
        text: text,
        riskScore: 0,
        warningLevel: 0,
        explanation: '정상적인 통화로 보입니다.',
      );
    }

    int score = 0;
    final lower = windowText.toLowerCase();

    for (final phrase in _highRiskPhrases) {
      if (lower.contains(phrase)) score += 30;
    }
    for (final kw in _keywords) {
      if (lower.contains(kw)) score += 10;
    }
    score = score.clamp(0, 100);

    final level = score >= 75 ? 3 : score >= 50 ? 2 : score >= 25 ? 1 : 0;

    final explanation = switch (level) {
      3 => '즉시 통화를 끊으세요. 보이스피싱 위험 키워드가 다수 감지됐습니다.',
      2 => '의심스러운 키워드가 감지됐습니다. 주의하세요.',
      1 => '일부 주의 키워드가 감지됐습니다.',
      _ => '정상적인 통화로 보입니다.',
    };

    return AnalysisResult(
      text: text,
      riskScore: score,
      warningLevel: level,
      explanation: explanation,
    );
  }
}
