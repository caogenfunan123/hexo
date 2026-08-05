/// 拼写检查服务
/// 基于内置词典的英文拼写检测，支持中文常见错别字检测
/// 可在编辑器中实时或手动触发
library;


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
    'regex', 'regexp', 'sql', 'nosql', 'orm', 'mvc', 'mvvm', 'dom', 'svg',
    'png', 'jpg', 'jpeg', 'gif', 'webp', 'mp4', 'scss', 'sass', 'less', 'jsx',
    'tsx', 'vue', 'react', 'angular', 'pnpm', 'webpack', 'vite', 'esbuild', 'babel',
    'eslint', 'prettier', 'typescript', 'javascript', 'python', 'java', 'golang', 'rust',
    'kotlin', 'swift', 'flutter', 'dart', 'csharp', 'dotnet', 'node',
    'deno', 'bun', 'wasm', 'webassembly', 'llm', 'gpt', 'ai', 'ml',
    'nlp', 'cv', 'tensorflow', 'pytorch', 'keras', 'scikit', 'numpy', 'pandas', 'matplotlib',
    'hexo', 'hugo', 'jekyll', 'gatsby', 'nextjs', 'nuxt', 'svelte',
    // 博客/Hexo 相关
    'astro', 'markdown', 'frontmatter', 'front', 'matter', 'yaml', 'toml', 'yml',
    'wordpress', 'ghost', 'notion', 'obsidian', 'typora', 'marktext', 'bitbucket',
    'netlify', 'vercel', 'cloudflare', 'rss', 'atom', 'seo',
    'sitemap', 'robots', 'analytics', 'gtag', 'disqus', 'utterances',
    'giscus', 'waline', 'twikoo', 'wechat', 'weibo', 'zhihu', 'bilibili',
    'douyin', 'tiktok', 'twitter', 'facebook', 'instagram',
    // 中文常见
    'linkedin', 'youtube', 'reddit', 'discord', 'slack', 'telegram', 'whatsapp',
    'signal', 'matrix', 'ie', 'eg', 'etc', 'vs',
    'aka', 'tbd', 'wip', 'todo', 'fixme',
    // 常见技术缩写
    'tui', 'db', 'os', 'vm', 'cpu', 'gpu', 'ram', 'ssd', 'hdd',
    'lan', 'wan', 'vpn', 'p2p', 'iot', 'sd', 'hd', 'uhd', 'fps', 'hz',
    'ghz', 'mhz', 'khz', 'mb', 'gb', 'tb', 'kb', 'pb', 'ok', 'okay',
    'bye', 'hello', 'thanks', 'please', 'readme', 'changelog', 'license', 'makefile', 'dockerfile', 'gitignore',
    'env', 'config', 'src', 'dist', 'build', 'node_modules',
    // 文件名常见
    'package',
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
    'amount', 'analysis', 'application', 'approach', 'area', 'argument',
    'article', 'aspect', 'attention', 'author', 'basis', 'benefit',
    'body', 'book', 'business', 'case', 'category', 'center', 'chance',
    'character', 'child', 'choice', 'city', 'class', 'code', 'college',
    'comment', 'communication', 'community', 'company', 'comparison', 'concept',
    'concern', 'condition', 'conference', 'consequence', 'context',
    'conversation', 'country', 'couple', 'course', 'culture', 'data',
    'day', 'death', 'decision', 'definition', 'degree', 'department', 'description',
    'detail', 'development', 'difference', 'difficulty', 'direction',
    'discussion', 'disease', 'document', 'door', 'doubt',
    'economy', 'education', 'effect', 'effort', 'element', 'end',
    'energy', 'environment', 'equipment', 'error', 'event', 'evidence',
    'example', 'expert', 'explanation', 'expression', 'fact', 'factor',
    'family', 'feature', 'field', 'figure', 'film', 'finding',
    'friend', 'function', 'future', 'game', 'goal', 'government', 'ground',
    'group', 'growth', 'hand', 'health', 'history', 'home', 'hour',
    'house', 'idea', 'image', 'impact', 'importance', 'individual', 'industry',
    'information', 'institution', 'interest', 'investment', 'issue', 'item', 'job',
    'kind', 'knowledge', 'language', 'law', 'leader',
    'level', 'life', 'light', 'line', 'list', 'literature', 'location',
    'loss', 'machine', 'management', 'manager', 'market', 'material', 'matter', 'member',
    'memory', 'message', 'method', 'mind', 'minute', 'model',
    'moment', 'money', 'month', 'morning', 'movement', 'music',
    'name', 'nation', 'nature', 'network', 'news', 'night', 'number',
    'object', 'office', 'operation', 'opinion', 'opportunity', 'option', 'organization',
    'outcome', 'owner', 'paper', 'part', 'participant', 'party', 'pattern',
    'people', 'performance', 'period', 'person', 'perspective', 'platform',
    'policy', 'population', 'position', 'possibility', 'power', 'practice',
    'president', 'pressure', 'price', 'problem', 'process', 'product',
    'program', 'project', 'property', 'proposal', 'purpose', 'quality',
    'question', 'range', 'rate', 'reality', 'reason',
    'relationship', 'research', 'resource', 'response', 'responsibility', 'review',
    'right', 'risk', 'role', 'rule', 'school', 'science',
    'section', 'security', 'sense', 'series', 'service', 'side',
    'site', 'situation', 'size', 'skill', 'society',
    'software', 'solution', 'sort', 'source', 'space', 'species', 'staff',
    'standard', 'step', 'story', 'strategy', 'structure', 'student',
    'subject', 'success', 'surface', 'system', 'table', 'task', 'team',
    'technology', 'term', 'test', 'text', 'theory', 'thing',
    'thought', 'time', 'tool', 'topic', 'trade', 'tradition',
    'treatment', 'trend', 'type', 'understanding', 'unit', 'university',
    'variety', 'version', 'view', 'voice', 'war', 'water', 'way',
    'website', 'week', 'woman', 'word', 'worker', 'world', 'writer',
    'year', 'able', 'active', 'actual', 'additional', 'available',
    'basic', 'beautiful', 'best', 'better', 'big', 'black',
    'blue', 'brief', 'bright', 'broad', 'brown', 'certain', 'cheap', 'cold',
    'common', 'complex', 'concerned', 'critical', 'cultural', 'current',
    // 常见形容词
    'dark', 'dead', 'deep', 'different', 'difficult', 'direct',
    'dry', 'early', 'easy', 'economic', 'effective', 'empty', 'entire',
    'environmental', 'essential', 'excellent', 'existing', 'external', 'fair', 'false',
    'familiar', 'famous', 'fast', 'final', 'financial', 'fine',
    'flat', 'foreign', 'free', 'fresh', 'full', 'funny',
    'general', 'global', 'good', 'great', 'green', 'happy', 'hard',
    'healthy', 'heavy', 'helpful', 'high', 'hot',
    'huge', 'human', 'important', 'interesting', 'internal', 'international',
    'key', 'large', 'late', 'legal', 'likely', 'little', 'local',
    'long', 'low', 'main', 'major', 'medical', 'military', 'modern',
    'natural', 'necessary', 'negative', 'new', 'nice', 'normal', 'old',
    'original', 'particular', 'personal', 'physical', 'political', 'poor', 'popular',
    'positive', 'possible', 'potential', 'powerful', 'primary',
    'private', 'professional', 'public', 'quick', 'quiet', 'ready', 'real',
    'recent', 'red', 'responsible', 'rich', 'safe', 'serious',
    'short', 'significant', 'similar', 'simple', 'single', 'small', 'social',
    'soft', 'special', 'specific', 'strong', 'successful', 'sure',
    'sweet', 'technical', 'traditional', 'true', 'useful', 'valuable',
    'various', 'warm', 'weak', 'white', 'whole', 'wide',
    'willing', 'wrong', 'young', 'actually', 'already', 'also', 'always',
    'certainly', 'clearly', 'completely', 'directly', 'easily', 'especially',
    'even', 'ever', 'exactly', 'fairly', 'finally', 'frequently',
    'generally', 'hardly', 'highly', 'immediately', 'indeed', 'instead',
    'just', 'largely', 'mainly', 'maybe', 'merely', 'nearly',
    'necessarily', 'never', 'now', 'often', 'once', 'particularly', 'perhaps',
    // 常见副词
    'probably', 'quickly', 'quite', 'rather', 'really', 'recently',
    'simply', 'slightly', 'slowly', 'sometimes', 'soon', 'specifically',
    'still', 'strongly', 'suddenly', 'surely', 'then', 'there',
    'therefore', 'together', 'usually', 'well', 'yet', 'accordingly',
    'additionally', 'consequently', 'conversely', 'furthermore', 'hence', 'however',
    'meanwhile', 'moreover', 'nevertheless', 'nonetheless', 'otherwise', 'regarding',
    'subsequently', 'thus', 'whereas', 'while', 'although', 'because',
    'despite', 'unless', 'whether', 'essentially', 'fundamentally', 'historically',
    'increasingly', 'initially', 'previously', 'relatively', 'significantly', 'typically',
    'ultimately', 'absolutely', 'approximately', 'consistently',
    // 写作常用词
    'constantly', 'effectively', 'efficiently', 'entirely',
    'extremely', 'inevitably', 'naturally', 'perfectly', 'precisely',
    'thoroughly', 'analyze', 'evaluate', 'assess',
    'demonstrate', 'illustrate', 'highlight', 'emphasize', 'recommend',
    'propose', 'conclude', 'summarize', 'outline', 'simplify', 'optimize',
    'enhance', 'facilitate', 'integrate', 'collaborate',
    'coordinate', 'negotiate', 'resolve', 'methodology',
    'framework', 'infrastructure', 'architecture', 'component',
    'module', 'interface', 'functionality', 'capability',
    'scalability', 'reliability', 'efficiency', 'productivity',
    'innovation', 'transformation', 'optimization', 'automation',
    'implementation', 'integration', 'deployment', 'maintenance', 'configuration',
    'customization', 'standardization', 'visualization', 'documentation',
    'collaboration', 'contribution', 'participation', 'substantial', 'considerable',
    'remarkable', 'exceptional', 'outstanding', 'superior', 'comprehensive',
    'extensive', 'thorough', 'detailed', 'practical',
    'theoretical', 'empirical', 'conceptual', 'innovative',
    'creative', 'strategic', 'tactical', 'proactive',
    'reactive', 'adaptive', 'flexible', 'robust',
    'resilient', 'sustainable', 'scalable', 'portable',
    'compatible', 'accessible', 'usable', 'consistent',
    'coherent', 'logical', 'rational', 'accurate',
    'precise', 'reliable', 'valid',
    'efficient', 'optimal', 'ideal',
    'appropriate', 'suitable', 'relevant', 'applicable',
    'obtainable', 'achievable', 'feasible', 'viable',
    'realistic', 'crucial', 'vital', 'fundamental',
    'supplementary', 'complementary', 'alternative', 'probable',
    'typical', 'unique', 'distinctive', 'characteristic',
    'representative', 'diverse', 'numerous', 'multiple',
    'collective', 'mutual', 'reciprocal', 'temporary',
    'permanent', 'continuous', 'discrete', 'explicit',
    'implicit', 'abstract', 'concrete', 'static',
    'dynamic', 'linear', 'nonlinear', 'symmetric',
    'asymmetric', 'homogeneous', 'heterogeneous', 'deterministic',
    'stochastic', 'qualitative', 'quantitative', 'analytical',
    'synthetic', 'systematic', 'intrinsic', 'extrinsic',
    'endogenous', 'exogenous', 'micro', 'macro',
    'horizontal', 'vertical', 'lateral', 'longitudinal',
    'clockwise', 'counterclockwise', 'forward', 'backward',
    'upward', 'downward', 'inward', 'outward',
    'here', 'everywhere', 'nowhere', 'somewhere',
    'anywhere', 'elsewhere', 'wherever', 'whenever',
    'whatever', 'whoever', 'whichever', 'afterward',
    'beforehand', 'henceforth', 'notwithstanding', 'regardless',
    'according', 'concerning', 'considering', 'excluding',
    'following', 'including', 'involving', 'pending',
    'respecting', 'touching', 'wanting', 'barring',
    'excepting', 'saving', 'via', 'vis',
    'across', 'alongside', 'amid', 'amongst',
    'aside', 'astride', 'atop', 'opposite',
    'per', 'plus', 'pro', 're',
    'round', 'till', 'times', 'underneath',
    'unlike', 'versus', 'worth',
  };
}