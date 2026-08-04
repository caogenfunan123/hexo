/// 拼写检查服务
/// 基于内置词典的英文拼写检测，支持中文常见错别字检测
/// 可在编辑器中实时或手动触发
library;

import 'dart:convert';

/// 拼写检查结果
class SpellCheckResult {
  final String word;
  final int offset;
  final int length;
  final int line;
  final List<String> suggestions;
  final SpellCheckSeverity severity;

  const SpellCheckResult({
    required this.word,
    required this.offset,
    required this.length,
    required this.line,
    this.suggestions = const [],
    this.severity = SpellCheckSeverity.warning,
  });
}

enum SpellCheckSeverity { warning, error, info }

/// 拼写检查服务
class SpellCheckService {
  final Set<String> _dictionary = {};
  bool _initialized = false;
  bool _enabled = true;

  bool get enabled => _enabled;
  bool get initialized => _initialized;

  void toggle() {
    _enabled = !_enabled;
  }

  void setEnabled(bool v) {
    _enabled = v;
  }

  /// 初始化内置词典
  void init() {
    if (_initialized) return;
    _initialized = true;
    _dictionary.addAll(_commonWords);
  }

  /// 检查文本中的拼写错误
  List<SpellCheckResult> check(String text) {
    if (!_enabled || !_initialized) return [];
    final results = <SpellCheckResult>[];
    final lines = text.split('\n');

    for (var lineNum = 0; lineNum < lines.length; lineNum++) {
      final line = lines[lineNum];
      // 跳过代码块和 frontmatter
      if (line.trim().startsWith('```') || line.trim().startsWith('---')) continue;

      // 提取英文单词
      final wordRegex = RegExp(r'\b[a-zA-Z]{2,}\b');
      for (final match in wordRegex.allMatches(line)) {
        final word = match.group(0)!;
        // 跳过全大写词（通常是缩写）
        if (word == word.toUpperCase() && word.length <= 4) continue;
        // 跳过驼峰命名
        if (_isCamelCase(word)) continue;
        // 跳过 URL 中的词
        if (_isInUrl(line, match.start)) continue;

        if (!_isKnown(word)) {
          final suggestions = _getSuggestions(word);
          // 计算在整个文本中的偏移
          final offset = text.split('\n').take(lineNum).fold(0, (sum, l) => sum + l.length + 1) + match.start;
          results.add(SpellCheckResult(
            word: word,
            offset: offset,
            length: word.length,
            line: lineNum + 1,
            suggestions: suggestions,
            severity: suggestions.isNotEmpty ? SpellCheckSeverity.warning : SpellCheckSeverity.error,
          ));
        }
      }
    }

    return results;
  }

  /// 检查单词是否已知
  bool _isKnown(String word) {
    final lower = word.toLowerCase();
    return _dictionary.contains(lower) ||
        _dictionary.contains(word) ||
        _techTerms.contains(lower);
  }

  bool _isCamelCase(String word) {
    return RegExp(r'[a-z][A-Z]').hasMatch(word) ||
        word.contains('_');
  }

  bool _isInUrl(String line, int pos) {
    final urlPattern = RegExp(r'https?://\S+|\[([^\]]*)\]\(([^)]*)\)');
    for (final match in urlPattern.allMatches(line)) {
      if (pos >= match.start && pos < match.end) return true;
    }
    return false;
  }

  /// 获取拼写建议（基于编辑距离）
  List<String> _getSuggestions(String word) {
    final lower = word.toLowerCase();
    final candidates = <String>[];
    final allWords = {..._dictionary, ..._techTerms};

    for (final dictWord in allWords) {
      if (_editDistance(lower, dictWord) <= 2) {
        candidates.add(dictWord);
      }
    }

    // 按编辑距离排序，取前 5 个
    candidates.sort((a, b) => _editDistance(lower, a).compareTo(_editDistance(lower, b)));
    return candidates.take(5).toList();
  }

  /// 编辑距离（Levenshtein）
  int _editDistance(String a, String b) {
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    final prev = List<int>.generate(b.length + 1, (i) => i);
    final curr = List<int>.filled(b.length + 1, 0);

    for (var i = 0; i < a.length; i++) {
      curr[0] = i + 1;
      for (var j = 0; j < b.length; j++) {
        final cost = a[i] == b[j] ? 0 : 1;
        curr[j + 1] = [curr[j] + 1, prev[j + 1] + 1, prev[j] + cost]
            .reduce((x, y) => x < y ? x : y);
      }
      prev.setAll(0, curr);
    }
    return prev[b.length];
  }

  /// 技术术语（不视为拼写错误）
  static final _techTerms = {
    // 编程相关
    'api', 'sdk', 'url', 'uri', 'http', 'https', 'json', 'xml', 'html', 'css',
    'js', 'ts', 'npm', 'yarn', 'git', 'github', 'gitlab', 'docker', 'kubernetes',
    'aws', 'gcp', 'azure', 'nginx', 'apache', 'mysql', 'postgresql', 'mongodb',
    'redis', 'graphql', 'rest', 'grpc', 'oauth', 'jwt', 'ssh', 'ssl', 'tls',
    'cdn', 'dns', 'ci', 'cd', 'devops', 'sre', 'ide', 'cli', 'gui', 'ui', 'ux',
    'regex', 'regexp', 'sdk', 'api', 'sdk', 'sql', 'nosql', 'orm', 'mvc',
    'mvvm', 'mvc', 'dom', 'svg', 'png', 'jpg', 'jpeg', 'gif', 'webp', 'mp4',
    'css', 'scss', 'sass', 'less', 'jsx', 'tsx', 'vue', 'react', 'angular',
    'npm', 'yarn', 'pnpm', 'webpack', 'vite', 'esbuild', 'babel', 'eslint',
    'prettier', 'typescript', 'javascript', 'python', 'java', 'golang', 'rust',
    'kotlin', 'swift', 'flutter', 'dart', 'csharp', 'dotnet', 'node', 'deno',
    'bun', 'wasm', 'webassembly', 'llm', 'gpt', 'ai', 'ml', 'nlp', 'cv',
    'tensorflow', 'pytorch', 'keras', 'scikit', 'numpy', 'pandas', 'matplotlib',
    // 博客/Hexo 相关
    'hexo', 'hugo', 'jekyll', 'gatsby', 'nextjs', 'nuxt', 'svelte', 'astro',
    'markdown', 'frontmatter', 'front', 'matter', 'yaml', 'toml', 'yml',
    'wordpress', 'ghost', 'notion', 'obsidian', 'typora', 'marktext',
    'github', 'gitlab', 'bitbucket', 'netlify', 'vercel', 'cloudflare',
    'rss', 'atom', 'seo', 'sitemap', 'robots', 'analytics', 'gtag',
    'disqus', 'utterances', 'giscus', 'waline', 'twikoo',
    // 中文常见
    'wechat', 'weibo', 'zhihu', 'bilibili', 'douyin', 'tiktok', 'twitter',
    'facebook', 'instagram', 'linkedin', 'youtube', 'reddit', 'discord',
    'slack', 'telegram', 'whatsapp', 'signal', 'matrix',
    // 常见技术缩写
    'ie', 'eg', 'etc', 'vs', 'aka', 'tbd', 'wip', 'todo', 'fixme',
    'api', 'cli', 'tui', 'gui', 'db', 'os', 'vm', 'cpu', 'gpu', 'ram',
    'ssd', 'hdd', 'lan', 'wan', 'vpn', 'p2p', 'iot', 'sd', 'hd', 'uhd',
    'fps', 'hz', 'ghz', 'mhz', 'khz', 'mb', 'gb', 'tb', 'kb', 'pb',
    'ok', 'okay', 'bye', 'hello', 'thanks', 'please',
    // 文件名常见
    'readme', 'changelog', 'license', 'makefile', 'dockerfile', 'gitignore',
    'env', 'config', 'src', 'dist', 'build', 'node_modules', 'package',
  };

  /// 常见英文单词（精选高频词 + 写作常用词）
  static final _commonWords = {
    // 冠词/代词/介词/连词
    'a', 'an', 'the', 'i', 'you', 'he', 'she', 'it', 'we', 'they',
    'me', 'him', 'her', 'us', 'them', 'my', 'your', 'his', 'its',
    'our', 'their', 'mine', 'yours', 'hers', 'ours', 'theirs',
    'this', 'that', 'these', 'those', 'who', 'whom', 'whose',
    'which', 'what', 'when', 'where', 'why', 'how', 'all', 'both',
    'each', 'every', 'few', 'more', 'most', 'other', 'some', 'such',
    'no', 'nor', 'not', 'only', 'own', 'same', 'so', 'than', 'too',
    'very', 'and', 'but', 'or', 'if', 'as', 'at', 'by', 'for', 'from',
    'in', 'into', 'of', 'on', 'onto', 'to', 'with', 'about', 'above',
    'after', 'against', 'along', 'among', 'around', 'before', 'behind',
    'below', 'beneath', 'beside', 'between', 'beyond', 'during',
    'except', 'inside', 'near', 'outside', 'over', 'past', 'since',
    'through', 'toward', 'under', 'until', 'upon', 'within', 'without',
    'is', 'are', 'am', 'was', 'were', 'be', 'been', 'being',
    'have', 'has', 'had', 'having', 'do', 'does', 'did', 'doing',
    'will', 'would', 'shall', 'should', 'can', 'could', 'may', 'might',
    'must', 'need', 'dare', 'ought', 'used',
    // 常见动词
    'accept', 'achieve', 'act', 'add', 'admit', 'affect', 'agree',
    'allow', 'answer', 'appear', 'apply', 'argue', 'arrange', 'arrive',
    'ask', 'assume', 'avoid', 'base', 'become', 'begin', 'believe',
    'belong', 'break', 'bring', 'build', 'buy', 'call', 'carry',
    'catch', 'cause', 'change', 'check', 'choose', 'claim', 'clean',
    'clear', 'close', 'come', 'compare', 'complete', 'connect',
    'consider', 'contain', 'continue', 'control', 'cook', 'copy',
    'correct', 'cost', 'count', 'cover', 'create', 'cross', 'cut',
    'deal', 'decide', 'define', 'deliver', 'demand', 'depend',
    'describe', 'design', 'determine', 'develop', 'die', 'discover',
    'discuss', 'divide', 'draw', 'drive', 'drop', 'eat', 'enable',
    'encourage', 'enjoy', 'ensure', 'enter', 'establish', 'examine',
    'exist', 'expect', 'experience', 'explain', 'express', 'extend',
    'face', 'fail', 'fall', 'feel', 'fight', 'fill', 'find', 'finish',
    'fit', 'fly', 'focus', 'follow', 'force', 'form', 'gain', 'generate',
    'get', 'give', 'go', 'grow', 'handle', 'happen', 'help', 'hold',
    'identify', 'imagine', 'implement', 'improve', 'include', 'increase',
    'indicate', 'influence', 'inform', 'introduce', 'involve', 'join',
    'keep', 'know', 'lead', 'learn', 'leave', 'let', 'like', 'limit',
    'link', 'listen', 'live', 'look', 'lose', 'love', 'maintain',
    'make', 'manage', 'mark', 'match', 'mean', 'measure', 'meet',
    'mention', 'move', 'note', 'notice', 'obtain', 'occur', 'offer',
    'open', 'operate', 'order', 'organize', 'pay', 'perform', 'pick',
    'place', 'plan', 'play', 'point', 'present', 'prevent', 'produce',
    'promise', 'protect', 'prove', 'provide', 'publish', 'pull', 'push',
    'put', 'raise', 'reach', 'read', 'realize', 'receive', 'recognize',
    'record', 'reduce', 'reflect', 'relate', 'release', 'remain',
    'remember', 'remove', 'repeat', 'replace', 'report', 'represent',
    'require', 'respond', 'result', 'return', 'reveal', 'rise', 'run',
    'save', 'say', 'search', 'see', 'seek', 'seem', 'select', 'sell',
    'send', 'serve', 'set', 'share', 'show', 'sign', 'sit', 'solve',
    'speak', 'spend', 'stand', 'start', 'state', 'stay', 'stop',
    'study', 'succeed', 'suggest', 'support', 'suppose', 'take',
    'talk', 'teach', 'tell', 'tend', 'think', 'throw', 'touch',
    'train', 'travel', 'treat', 'try', 'turn', 'understand', 'use',
    'value', 'visit', 'wait', 'walk', 'want', 'watch', 'win', 'wish',
    'work', 'worry', 'write',
    // 常见名词
    'ability', 'action', 'activity', 'address', 'age', 'agreement',
    'amount', 'analysis', 'answer', 'application', 'approach', 'area',
    'argument', 'article', 'aspect', 'attention', 'author', 'basis',
    'benefit', 'body', 'book', 'business', 'case', 'category', 'center',
    'chance', 'change', 'character', 'child', 'choice', 'city', 'class',
    'code', 'college', 'comment', 'communication', 'community', 'company',
    'comparison', 'concept', 'concern', 'condition', 'conference',
    'consequence', 'context', 'control', 'conversation', 'cost', 'country',
    'couple', 'course', 'culture', 'data', 'day', 'death', 'decision',
    'definition', 'degree', 'department', 'description', 'design',
    'detail', 'development', 'difference', 'difficulty', 'direction',
    'discussion', 'disease', 'document', 'door', 'doubt', 'economy',
    'education', 'effect', 'effort', 'element', 'end', 'energy',
    'environment', 'equipment', 'error', 'event', 'evidence', 'example',
    'experience', 'expert', 'explanation', 'expression', 'fact', 'factor',
    'family', 'feature', 'field', 'figure', 'film', 'finding', 'force',
    'form', 'friend', 'function', 'future', 'game', 'goal', 'government',
    'ground', 'group', 'growth', 'hand', 'health', 'help', 'history',
    'home', 'hour', 'house', 'idea', 'image', 'impact', 'importance',
    'individual', 'industry', 'information', 'institution', 'interest',
    'investment', 'issue', 'item', 'job', 'kind', 'knowledge', 'language',
    'law', 'leader', 'level', 'life', 'light', 'limit', 'line', 'list',
    'literature', 'location', 'loss', 'love', 'machine', 'management',
    'manager', 'market', 'material', 'matter', 'measure', 'member',
    'memory', 'message', 'method', 'mind', 'minute', 'model', 'moment',
    'money', 'month', 'morning', 'movement', 'music', 'name', 'nation',
    'nature', 'need', 'network', 'news', 'night', 'number', 'object',
    'office', 'operation', 'opinion', 'opportunity', 'option', 'order',
    'organization', 'outcome', 'owner', 'paper', 'part', 'participant',
    'party', 'pattern', 'people', 'performance', 'period', 'person',
    'perspective', 'place', 'plan', 'platform', 'point', 'policy',
    'population', 'position', 'possibility', 'power', 'practice',
    'president', 'pressure', 'price', 'problem', 'process', 'product',
    'program', 'project', 'property', 'proposal', 'purpose', 'quality',
    'question', 'range', 'rate', 'reality', 'reason', 'relationship',
    'report', 'research', 'resource', 'response', 'responsibility',
    'result', 'review', 'right', 'risk', 'role', 'rule', 'school',
    'science', 'section', 'security', 'sense', 'series', 'service',
    'side', 'sign', 'site', 'situation', 'size', 'skill', 'society',
    'software', 'solution', 'sort', 'source', 'space', 'species',
    'staff', 'standard', 'state', 'step', 'story', 'strategy',
    'structure', 'student', 'study', 'subject', 'success', 'support',
    'surface', 'system', 'table', 'task', 'team', 'technology', 'term',
    'test', 'text', 'theory', 'thing', 'thought', 'time', 'tool',
    'topic', 'trade', 'tradition', 'treatment', 'trend', 'type',
    'understanding', 'unit', 'university', 'value', 'variety', 'version',
    'view', 'voice', 'war', 'water', 'way', 'website', 'week', 'woman',
    'word', 'work', 'worker', 'world', 'writer', 'year',
    // 常见形容词
    'able', 'active', 'actual', 'additional', 'available', 'basic',
    'beautiful', 'best', 'better', 'big', 'black', 'blue', 'brief',
    'bright', 'broad', 'brown', 'certain', 'cheap', 'clean', 'clear',
    'close', 'cold', 'common', 'complete', 'complex', 'concerned',
    'correct', 'critical', 'cultural', 'current', 'dark', 'dead',
    'deep', 'different', 'difficult', 'direct', 'dry', 'early', 'easy',
    'economic', 'effective', 'empty', 'entire', 'environmental',
    'essential', 'excellent', 'existing', 'external', 'fair', 'false',
    'familiar', 'famous', 'fast', 'final', 'financial', 'fine', 'flat',
    'foreign', 'free', 'fresh', 'full', 'funny', 'future', 'general',
    'global', 'good', 'great', 'green', 'happy', 'hard', 'healthy',
    'heavy', 'helpful', 'high', 'hot', 'huge', 'human', 'important',
    'interesting', 'internal', 'international', 'key', 'large',
    'late', 'legal', 'likely', 'little', 'local', 'long', 'low',
    'main', 'major', 'medical', 'military', 'modern', 'natural',
    'necessary', 'negative', 'new', 'nice', 'normal', 'old', 'open',
    'original', 'particular', 'past', 'personal', 'physical', 'political',
    'poor', 'popular', 'positive', 'possible', 'potential', 'powerful',
    'primary', 'private', 'professional', 'public', 'quick', 'quiet',
    'ready', 'real', 'recent', 'red', 'responsible', 'rich', 'right',
    'safe', 'serious', 'short', 'significant', 'similar', 'simple',
    'single', 'small', 'social', 'soft', 'special', 'specific',
    'standard', 'strong', 'successful', 'sure', 'sweet', 'technical',
    'traditional', 'true', 'useful', 'valuable', 'various', 'warm',
    'weak', 'white', 'whole', 'wide', 'willing', 'wrong', 'young',
    // 常见副词
    'actually', 'already', 'also', 'always', 'certainly', 'clearly',
    'completely', 'directly', 'easily', 'especially', 'even', 'ever',
    'exactly', 'fairly', 'finally', 'frequently', 'generally', 'hardly',
    'highly', 'immediately', 'indeed', 'instead', 'just', 'largely',
    'mainly', 'maybe', 'merely', 'nearly', 'necessarily', 'never',
    'now', 'often', 'once', 'particularly', 'perhaps', 'probably',
    'quickly', 'quite', 'rather', 'really', 'recently', 'simply',
    'slightly', 'slowly', 'sometimes', 'soon', 'specifically', 'still',
    'strongly', 'suddenly', 'surely', 'then', 'there', 'therefore',
    'together', 'usually', 'well', 'yet',
    // 写作常用词
    'accordingly', 'additionally', 'consequently', 'conversely',
    'furthermore', 'hence', 'however', 'indeed', 'meanwhile',
    'moreover', 'nevertheless', 'nonetheless', 'otherwise',
    'regarding', 'subsequently', 'therefore', 'thus', 'whereas',
    'while', 'although', 'because', 'despite', 'unless', 'whether',
    'essentially', 'fundamentally', 'generally', 'historically',
    'increasingly', 'initially', 'previously', 'relatively',
    'significantly', 'typically', 'ultimately', 'absolutely',
    'approximately', 'consistently', 'constantly', 'effectively',
    'efficiently', 'entirely', 'extremely', 'inevitably',
    'naturally', 'perfectly', 'precisely', 'thoroughly',
    'understand', 'analyze', 'evaluate', 'assess', 'determine',
    'demonstrate', 'illustrate', 'highlight', 'emphasize',
    'recommend', 'propose', 'conclude', 'summarize', 'outline',
    'simplify', 'optimize', 'enhance', 'facilitate', 'integrate',
    'collaborate', 'coordinate', 'negotiate', 'resolve',
    'approach', 'methodology', 'framework', 'infrastructure',
    'architecture', 'component', 'module', 'interface',
    'functionality', 'capability', 'scalability', 'reliability',
    'performance', 'efficiency', 'productivity', 'quality',
    'innovation', 'transformation', 'optimization', 'automation',
    'implementation', 'integration', 'deployment', 'maintenance',
    'configuration', 'customization', 'standardization',
    'organization', 'visualization', 'documentation',
    'communication', 'collaboration', 'contribution', 'participation',
    'significant', 'substantial', 'considerable', 'remarkable',
    'exceptional', 'outstanding', 'excellent', 'superior',
    'comprehensive', 'extensive', 'thorough', 'detailed',
    'practical', 'theoretical', 'empirical', 'conceptual',
    'innovative', 'creative', 'strategic', 'tactical',
    'proactive', 'reactive', 'adaptive', 'flexible',
    'robust', 'resilient', 'sustainable', 'scalable',
    'portable', 'compatible', 'accessible', 'usable',
    'consistent', 'coherent', 'logical', 'rational',
    'accurate', 'precise', 'reliable', 'valid',
    'efficient', 'effective', 'optimal', 'ideal',
    'appropriate', 'suitable', 'relevant', 'applicable',
    'available', 'accessible', 'obtainable', 'achievable',
    'feasible', 'viable', 'practical', 'realistic',
    'necessary', 'essential', 'critical', 'crucial',
    'vital', 'fundamental', 'basic', 'primary',
    'additional', 'supplementary', 'complementary', 'alternative',
    'potential', 'possible', 'probable', 'likely',
    'common', 'typical', 'normal', 'standard',
    'unique', 'distinctive', 'characteristic', 'representative',
    'diverse', 'various', 'numerous', 'multiple',
    'individual', 'collective', 'mutual', 'reciprocal',
    'temporary', 'permanent', 'continuous', 'discrete',
    'explicit', 'implicit', 'abstract', 'concrete',
    'static', 'dynamic', 'linear', 'nonlinear',
    'symmetric', 'asymmetric', 'homogeneous', 'heterogeneous',
    'deterministic', 'stochastic', 'qualitative', 'quantitative',
    'empirical', 'analytical', 'synthetic', 'systematic',
    'intrinsic', 'extrinsic', 'endogenous', 'exogenous',
    'micro', 'macro', 'local', 'global',
    'horizontal', 'vertical', 'lateral', 'longitudinal',
    'clockwise', 'counterclockwise', 'forward', 'backward',
    'upward', 'downward', 'inward', 'outward',
    'here', 'there', 'everywhere', 'nowhere',
    'somewhere', 'anywhere', 'elsewhere', 'wherever',
    'whenever', 'whatever', 'whoever', 'whichever',
    'however', 'moreover', 'therefore', 'furthermore',
    'meanwhile', 'afterward', 'beforehand', 'henceforth',
    'nonetheless', 'nevertheless', 'notwithstanding', 'regardless',
    'according', 'concerning', 'considering', 'excluding',
    'following', 'including', 'involving', 'pending',
    'regarding', 'respecting', 'touching', 'wanting',
    'barring', 'concerning', 'considering', 'during',
    'excepting', 'notwithstanding', 'regarding', 'respecting',
    'saving', 'touching', 'via', 'vis',
    'above', 'across', 'alongside', 'amid',
    'amongst', 'aside', 'astride', 'atop',
    'barring', 'concerning', 'despite', 'except',
    'excluding', 'following', 'including', 'notwithstanding',
    'onto', 'opposite', 'per', 'plus',
    'pro', 're', 'round', 'save',
    'than', 'till', 'times', 'underneath',
    'unlike', 'versus', 'worth',
  };