/// Chat languages — keys match the server (src/translate.js).
class Lang {
  final String code, flag, name;
  const Lang(this.code, this.flag, this.name);

  static const all = [
    Lang('th', '🇹🇭', 'ไทย'),
    Lang('en', '🇬🇧', 'English'),
    Lang('zh', '🇨🇳', '中文'),
    Lang('ja', '🇯🇵', '日本語'),
    Lang('ko', '🇰🇷', '한국어'),
    Lang('ru', '🇷🇺', 'Русский'),
    Lang('de', '🇩🇪', 'Deutsch'),
    Lang('fr', '🇫🇷', 'Français'),
  ];
  static Lang of(String code) => all.firstWhere((l) => l.code == code, orElse: () => all.first);
}
