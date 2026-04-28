import 'dart:convert';
import 'package:http/http.dart' as http;

class LlmService {
  static const _endpoint = 'https://api.openai.com/v1/chat/completions';
  static const _model = 'gpt-4o-mini';

  final String _apiKey;
  LlmService(this._apiKey);

  Future<String> explain({
    required String text,
    required List<String> detected,
    required int score,
  }) async {
    if (_apiKey.isEmpty) return '';

    final prompt = '전화 통화 내용: "$text"\n'
        '탐지된 보이스피싱 패턴: ${detected.join(', ')}\n'
        '위험도 점수: $score/100\n\n'
        '위 내용을 바탕으로 이 통화가 왜 보이스피싱으로 의심되는지 '
        '사용자에게 2문장 이내로 간결하게 한국어로 설명하세요. '
        '마크다운, 번호, 제목 없이 설명만 작성하세요.';

    try {
      final response = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Authorization': 'Bearer $_apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': _model,
              'max_tokens': 150,
              'messages': [
                {'role': 'user', 'content': prompt}
              ],
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return '';
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = data['choices'] as List?;
      if (choices == null || choices.isEmpty) return '';
      return (choices[0]['message']['content'] as String? ?? '').trim();
    } catch (_) {
      return '';
    }
  }
}
