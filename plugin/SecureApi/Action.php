<?php
namespace TypechoPlugin\SecureApi;

use Widget\ActionInterface;
use Typecho\Widget;
use Typecho\Db;
use Typecho\Router;
use Typecho\Common;
use Utils\Markdown;
use Widget\Options;

/*
 * Copyright (c) 2025 笨小猪
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/**
 * 接口处理类（Typecho 1.3.0 原生命名空间）
 *
 * 本文件为增强版：在官方 SecureApi 只读接口的基础上，
 * 新增文章写入能力，供 Hexo 博客管理 App 调用：
 *   - createPost   创建/发布文章（POST，表单参数）
 *   - updatePost   更新文章（POST，表单参数）
 *   - deletePost   删除文章
 *   - uploadMedia  上传媒体文件（multipart/form-data）
 */
class Action extends Widget implements ActionInterface
{
    /**
     * 系统配置对象
     * @var \Widget\Options
     */
    private $options;
    
    /**
     * 插件配置
     * @var array
     */
    private $config;

    /**
     * 扩展列缓存
     * @var array|null
     */
    private static $extraColumns = null;

    /**
     * 检查扩展列（views/agree）是否存在
     */
    private function hasColumn($columnName)
    {
        if (self::$extraColumns === null) {
            self::$extraColumns = ['views' => false, 'agree' => false];
            try {
                $db = Db::get();
                $prefix = $db->getPrefix();
                $table = $prefix . 'contents';
                $row = $db->fetchRow("SHOW COLUMNS FROM `{$table}` LIKE 'views'");
                self::$extraColumns['views'] = !empty($row);
                $row = $db->fetchRow("SHOW COLUMNS FROM `{$table}` LIKE 'agree'");
                self::$extraColumns['agree'] = !empty($row);
            } catch (\Exception $e) {
                // 检测失败则默认不存在
            }
        }
        return self::$extraColumns[$columnName] ?? false;
    }
    
    /**
     * 构造函数
     * 
     * @param \Widget\Request $request
     * @param \Widget\Response $response
     * @param array $params
     */
    public function __construct($request, $response, $params = [])
    {
        parent::__construct($request, $response, $params);
        
        // 初始化系统配置
        $this->options = Options::alloc();
        $this->config = Plugin::getConfig();
    }
    
    /**
     * 执行接口动作
     * 
     * @access public
     * @return void
     */
    public function action()
    {
        // 设置响应类型为JSON
        header('Content-Type: application/json; charset=utf-8');
        
        // 允许跨域请求（CORS），写入类接口使用 POST
        header('Access-Control-Allow-Origin: *');
        header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
        header('Access-Control-Allow-Headers: Content-Type, X-API-Key');
        
        // 处理 OPTIONS 预检请求
        if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
            http_response_code(204);
            exit;
        }
        
        try {
            // 安全验证
            $this->validateAccess();
            
            // 获取请求参数，默认动作为getPosts
            $action = $this->request->get('action', 'getPosts');
            
            // 根据不同动作返回不同数据
            switch ($action) {
                case 'getPosts'://获取文章列表
                    $this->getPosts();
                    break;
                case 'getCategories'://获取分类列表
                    $this->getCategories();
                    break;
                case 'getPages'://获取单页面列表
                    $this->getPages();
                    break;
                case 'getWebInfo'://获取网站信息
                    $this->getWebInfo();
                    break;
                case 'getCategoryPosts'://获取分类下的文章列表
                    $this->getCategoryPosts();
                    break;
                case 'search'://文章搜索功能
                    $this->searchPosts();
                    break;
                case 'getArticleContent'://获取文章内容
                    $this->getArticleContent();
                    break;
                case 'getAllTags'://获取所有标签
                    $this->getAllTags();
                    break;
                case 'articleAgree'://文章点赞/取消点赞
                    $this->articleAgree();
                    break;
                // ── 以下为增强写操作（Hexo 博客管理 App 调用） ──
                case 'createPost'://创建/发布文章
                    $this->createPost();
                    break;
                case 'updatePost'://更新文章
                    $this->updatePost();
                    break;
                case 'deletePost'://删除文章
                    $this->deletePost();
                    break;
                case 'uploadMedia'://上传媒体文件
                    $this->uploadMedia();
                    break;
                default:
                    throw new \Exception('无效的动作', 400);
            }
        } catch (\Exception $e) {
            $this->sendError($e->getMessage(), $e->getCode());
        }
    }
    
    /**
     * 访问验证
     * 
     * @access private
     * @return void
     * @throws \Exception
     */
    private function validateAccess()
    {
        $apiEnabled = isset($this->config['apiEnabled']) ? $this->config['apiEnabled'] : '0';
        $apiKey = isset($this->config['apiKey']) ? $this->config['apiKey'] : '';
        
        // 检查API是否开启
        if ($apiEnabled !== '1') {
            throw new \Exception('API功能已关闭，请在后台开启后再使用', 403);
        }
        
        // 验证密钥是否已设置
        if (empty($apiKey)) {
            throw new \Exception('API密钥未设置，请先在后台配置', 403);
        }
        
        // 密钥验证
        $requestKey = $this->request->get('token') ?? $this->request->getHeader('X-API-Key') ?? '';
        if (empty($requestKey) || $requestKey !== $apiKey) {
            throw new \Exception('无效的API密钥', 401);
        }
    }
    
    /**
     * 获取文章列表
     * 
     * @access private
     * @return void
     */
    private function getPosts()
    {
        $page = max(1, $this->request->get('page', 1));
        $limit = max(1, min(100, $this->request->get('limit', 10)));
        $offset = ($page - 1) * $limit;
        $status = $this->request->get('status', 'publish');
        if (!in_array($status, ['publish', 'draft', 'hidden', 'private', 'waiting', 'all'])) {
            $status = 'publish';
        }
        
        $db = Db::get();
        $prefix = $db->getPrefix();
        
        // 查询文章总数
        $totalQuery = $db->select(['COUNT(*)' => 'total'])
            ->from($prefix . 'contents')
            ->where('type = ?', 'post');
        if ($status !== 'all') {
            $totalQuery->where('status = ?', $status);
        }
        $total = $db->fetchObject($totalQuery)->total;
        
        // 查询文章列表
        $postQuery = $db->select()
            ->from($prefix . 'contents')
            ->where('type = ?', 'post');
        if ($status !== 'all') {
            $postQuery->where('status = ?', $status);
        }
        $posts = $db->fetchAll($postQuery
            ->order('created', Db::SORT_DESC)
            ->limit($limit)
            ->offset($offset));
        
        // 处理文章数据
        $result = [];
        foreach ($posts as $post) {
            // 获取文章标签
            $tagQuery = $db->select('name')->from($prefix . 'metas')
                ->join($prefix . 'relationships', $prefix . 'relationships.mid = ' . $prefix . 'metas.mid')
                ->where($prefix . 'relationships.cid = ?', $post['cid'])
                ->where('type = ?', 'tag');
            $tags = $db->fetchAll($tagQuery);

            // 获取文章分类
            $categoryQuery = $db->select('name', 'slug')->from($prefix . 'metas')
                ->join($prefix . 'relationships', $prefix . 'relationships.mid = ' . $prefix . 'metas.mid')
                ->where($prefix . 'relationships.cid = ?', $post['cid'])
                ->where('type = ?', 'category');
            $categories = $db->fetchAll($categoryQuery);

            // 使用Typecho的路由系统生成文章链接
            $permalink = Router::url('post', $post, $this->options->siteUrl);
            
            $result[] = [
                'id' => $post['cid'],
                'cid' => $post['cid'],
                'title' => $post['title'],
                'slug' => $post['slug'],
                'content' => $this->convertContent($post['text']),
                'created' => date('Y-m-d H:i:s', $post['created']),
                'updated' => date('Y-m-d H:i:s', $post['modified']),
                'authorId' => $post['authorId'],
                'commentsNum' => $post['commentsNum'],
                'views' => (int)($post['views'] ?? 0),
                'agree' => (int)($post['agree'] ?? 0),
                'status' => $post['status'],
                'permalink' => $permalink,
                'tags' => array_column($tags, 'name'),
                'categories' => array_map(function ($cate) {
                    return ['name' => $cate['name'], 'slug' => $cate['slug']];
                }, $categories),
                'summary' => mb_substr(strip_tags($this->convertContent($post['text'])), 0, 200) . '...',
                'random_image' => $this->getRandomImage()
            ];
        }

        $this->sendResponse([
            'total' => $total,
            'page' => $page,
            'limit' => $limit,
            'pages' => ceil($total / $limit),
            'data' => $result
        ]);
    }
    
    /**
     * 获取分类列表
     * 
     * @access private
     * @return void
     */
    private function getCategories()
    {
        $db = Db::get();
        $prefix = $db->getPrefix();
        
        // 获取所有分类（包含parent字段）
        $query = $db->select('mid', 'name', 'slug', 'count', 'parent', 'description')
            ->from($prefix . 'metas')
            ->where('type = ?', 'category')
            ->order('order', Db::SORT_ASC)
            ->order('name', Db::SORT_ASC);

        $categories = $db->fetchAll($query);
        // 构建分类映射表（id => 分类信息）
        $categoryMap = [];
        foreach ($categories as $category) {
            // 使用Typecho路由系统生成URL
            $routeParams = [
                'slug' => $category['slug'],
                'parent' => $category['parent'],
                'mid' => $category['mid']
            ];
            // 生成分类URL
            $url = Router::url('category', $routeParams);
            // 替换URL中的占位符为实际值
            if ($url) {
                $url = str_replace(['{mid}', '{slug}'], [$category['mid'], $category['slug']], $url);
            } else {
                // fallback机制
                $url = Common::url('/category/' . $category['slug'], $this->options->siteUrl);
            }
            $categoryMap[$category['mid']] = [
                'id' => $category['mid'],
                'name' => $category['name'],
                'slug' => $category['slug'],
                'description' => $category['description'],
                'count' => (int)$category['count'],
                'parent' => $category['parent'],
                'url' => $url,
                'children' => []
            ];
        }
        // 构建层级结构
        $result = [];
        foreach ($categoryMap as $id => $category) {
            if ($category['parent'] == 0) {
                $result[] = &$categoryMap[$id];
            } else {
                if (isset($categoryMap[$category['parent']])) {
                    $categoryMap[$category['parent']]['children'][] = &$categoryMap[$id];
                }
            }
        }
        unset($categoryMap);

        // 检查是否开启"隐藏空分类"（用于绕过微信审核）
        $hideEmptyCategories = isset($this->config['hideEmptyCategories']) && $this->config['hideEmptyCategories'] === '1';
        if ($hideEmptyCategories) {
            $result = $this->filterEmptyCategories($result);
        }

        $this->sendResponse($result);
    }

    /**
     * 递归过滤空分类（整个子树 count 均为 0 的分类将被隐藏）
     * 
     * @access private
     * @param array $categories 分类列表
     * @return array 过滤后的分类列表
     */
    private function filterEmptyCategories($categories)
    {
        $filtered = [];
        foreach ($categories as $cat) {
            if (!empty($cat['children'])) {
                $cat['children'] = $this->filterEmptyCategories($cat['children']);
            }
            $isEmpty = ((int)$cat['count'] === 0) && empty($cat['children']);
            if (!$isEmpty) {
                $filtered[] = $cat;
            }
        }
        return $filtered;
    }
    
    /**
     * 获取页面列表
     * 
     * @access private
     * @return void
     */
    private function getPages()
    {
        $db = Db::get();
        $prefix = $db->getPrefix();
        
        $pages = $db->fetchAll($db->select()
            ->from($prefix . 'contents')
            ->where('type = ?', 'page')
            ->where('status = ?', 'publish')
            ->order('created', Db::SORT_DESC));
        
        $result = [];
        foreach ($pages as $page) {
            $result[] = [
                'id' => $page['cid'],
                'title' => $page['title'],
                'content' => $this->convertContent($page['text']),
                'created' => date('Y-m-d H:i:s', $page['created']),
                'updated' => date('Y-m-d H:i:s', $page['modified']),
                'authorId' => $page['authorId'],
                'status' => $page['status'],
                'permalink' => Common::url('/index.php/' . $page['slug'], $this->options->siteUrl)
            ];
        }
        
        $this->sendResponse($result);
    }
    
    /**
     * 获取网站信息
     * 
     * @access private
     * @return void
     */
    private function getWebInfo()
    {
        $db = Db::get();
        $prefix = $db->getPrefix();
        
        // 获取所有配置项
        $optionsTable = $prefix . 'options';
        $options = $db->fetchAll($db->select()->from($optionsTable));

        $optionsMap = [];
        foreach ($options as $option) {
            $optionsMap[$option['name']] = $option['value'];
        }

        $result = [
            'title' => $optionsMap['title'] ?? '',
            'description' => $optionsMap['description'] ?? '',
            'keywords' => $optionsMap['keywords'] ?? '',
            'theme' => $optionsMap['theme'] ?? '',
            'siteUrl' => $optionsMap['siteUrl'] ?? '',
            'timezone' => $optionsMap['timezone'] ?? '',
            'charset' => $optionsMap['charset'] ?? '',
            'version' => Common::VERSION,
            'postCount' => $db->fetchObject($db->select(['COUNT(*)' => 'num'])
                ->from($prefix . 'contents')
                ->where('type = ?', 'post')
                ->where('status = ?', 'publish'))->num
        ];

        // 添加分享信息
        if (isset($this->config['shareConfig'])) {
            $shareConfig = explode('|', $this->config['shareConfig']);
            $result['share'] = [
                'share_image' => $shareConfig[0] ?? '',
                'share_texts' => [
                    'forward_to_friend' => $shareConfig[1] ?? '',
                    'share_to_moments' => $shareConfig[2] ?? ''
                ]
            ];
        }

        $this->sendResponse($result);
    }
    
    /**
     * 获取分类下的文章列表
     * 
     * @access private
     * @return void
     */
    private function getCategoryPosts()
    {
        $db = Db::get();
        $prefix = $db->getPrefix();
        $table = $prefix . 'contents';
        
        $category = trim($this->request->get('category', ''));
        if (empty($category)) {
            throw new \Exception('分类名称/缩略名/mid不能为空');
        }
        // 支持通过mid、name或slug查找分类
        $metaQuery = $db->select('mid', 'name', 'slug')
            ->from($prefix . 'metas')
            ->where('type = ?', 'category');
            
        if (is_numeric($category)) {
            $metaQuery->where('mid = ?', $category);
        } else {
            $metaQuery->where('(name = ? OR slug = ?)', $category, $category);
        }

        $categoryInfo = $db->fetchRow($metaQuery);

        if (empty($categoryInfo)) {
            throw new \Exception('指定分类不存在');
        }

        $page = max(1, intval($this->request->get('page', 1)));
        $pageSize = max(1, min(100, intval($this->request->get('pageSize', 10))));
        $offset = ($page - 1) * $pageSize;

        // 获取总数
        $totalQuery = $db->select(['COUNT(*)' => 'num'])
            ->from($table)
            ->join($prefix . 'relationships', $table . '.cid = ' . $prefix . 'relationships.cid', Db::INNER_JOIN)
            ->where($prefix . 'relationships.mid = ?', $categoryInfo['mid'])
            ->where($table . '.type = ?', 'post')
            ->where($table . '.status = ?', 'publish');

        $total = $db->fetchObject($totalQuery)->num;

        // 构建列列表（views/agree 为扩展列，可能不存在）
        $selectColumns = [
            $table . '.cid',
            $table . '.title',
            $table . '.slug',
            $table . '.created',
            $table . '.authorId',
            $table . '.text',
            $table . '.commentsNum',
        ];
        if ($this->hasColumn('views')) {
            $selectColumns[] = $table . '.views';
        }
        if ($this->hasColumn('agree')) {
            $selectColumns[] = $table . '.agree';
        }
        // 获取文章列表
        $postQuery = call_user_func_array([$db, 'select'], $selectColumns)
            ->from($table)
            ->join($prefix . 'relationships', $table . '.cid = ' . $prefix . 'relationships.cid', Db::INNER_JOIN)
            ->where($prefix . 'relationships.mid = ?', $categoryInfo['mid'])
            ->where($table . '.type = ?', 'post')
            ->where($table . '.status = ?', 'publish')
            ->order($table . '.created', Db::SORT_DESC)
            ->limit($pageSize)
            ->offset($offset);

        $articles = $db->fetchAll($postQuery);

        $result = [];
        foreach ($articles as $article) {
            $tagQuery = $db->select('name')
                ->from($prefix . 'metas')
                ->join($prefix . 'relationships', $prefix . 'relationships.mid = ' . $prefix . 'metas.mid')
                ->where($prefix . 'relationships.cid = ?', $article['cid'])
                ->where('type = ?', 'tag');
            $tags = $db->fetchAll($tagQuery);

            $result[] = [
                'cid' => $article['cid'],
                'title' => $article['title'],
                'slug' => $article['slug'],
                'created' => date('Y-m-d H:i:s', $article['created']),
                'authorId' => $article['authorId'],
                'commentsNum' => $article['commentsNum'],
                'views' => (int)($article['views'] ?? 0),
                'agree' => (int)($article['agree'] ?? 0),
                'tags' => array_column($tags, 'name'),
                'summary' => mb_substr(strip_tags($this->convertContent($article['text'])), 0, 200) . '...'
            ];
        }

        $this->sendResponse([
            'category_info' => [
                'name' => $categoryInfo['name'],
                'slug' => $categoryInfo['slug'],
                'mid' => $categoryInfo['mid'],
                'total_posts' => $total
            ],
            'data' => $result,
            'pagination' => [
                'total' => $total,
                'page' => $page,
                'pageSize' => $pageSize,
                'totalPages' => ceil($total / $pageSize)
            ]
        ]);
    }
    
    /**
     * 获取文章内容
     * 
     * @access private
     * @return void
     */
    private function getArticleContent()
    {
        $db = Db::get();
        $prefix = $db->getPrefix();
        $table = $prefix . 'contents';
        $cid = intval($this->request->get('cid', 0));
        if (empty($cid)) {
            throw new \Exception('文章CID不能为空');
        }

        // 构建列列表（views/agree 为扩展列，可能不存在）
        $selectColumns = [
            'cid', 'title', 'slug', 'created', 'modified',
            'authorId', 'text', 'status',
            'allowComment', 'allowPing', 'allowFeed',
            'commentsNum',
        ];
        if ($this->hasColumn('views')) {
            $selectColumns[] = 'views';
        }
        if ($this->hasColumn('agree')) {
            $selectColumns[] = 'agree';
        }

        $query = call_user_func_array([$db, 'select'], $selectColumns)
            ->from($table)
            ->where('type = ?', 'post')
            ->where('status = ?', 'publish')
            ->where('cid = ?', $cid);

        $article = $db->fetchRow($query);
        if (empty($article)) {
            throw new \Exception('文章不存在或未发布');
        }

        // 每次访问都增加阅读量（仅当 views 列存在时）
        if ($this->hasColumn('views')) {
            $db->query($db->update($table)
                ->rows(['views' => (int)$article['views'] + 1])
                ->where('cid = ?', $cid));
            $article['views'] = (int)$article['views'] + 1;
        }

        // 获取文章标签
        $tagQuery = $db->select('name', 'slug')->from($prefix . 'metas')
            ->join($prefix . 'relationships', $prefix . 'relationships.mid = ' . $prefix . 'metas.mid')
            ->where($prefix . 'relationships.cid = ?', $article['cid'])
            ->where('type = ?', 'tag');
        $tags = $db->fetchAll($tagQuery);

        // 获取文章分类
        $categoryQuery = $db->select('name', 'slug')->from($prefix . 'metas')
            ->join($prefix . 'relationships', $prefix . 'relationships.mid = ' . $prefix . 'metas.mid')
            ->where($prefix . 'relationships.cid = ?', $article['cid'])
            ->where('type = ?', 'category');
        $categories = $db->fetchAll($categoryQuery);

        // 获取作者信息
        $authorQuery = $db->select('name', 'screenName', 'url')
            ->from($prefix . 'users')
            ->where('uid = ?', $article['authorId']);
        $author = $db->fetchRow($authorQuery);

        // 获取文章评论
        $commentsQuery = $db->select('coid', 'cid', 'author', 'text', 'created')
            ->from($prefix . 'comments')
            ->where('cid = ?', $cid)
            ->where('status = ?', 'approved')
            ->order('created', Db::SORT_DESC);
        $comments = $db->fetchAll($commentsQuery);

        // 获取上一篇文章
        $prevQuery = $db->select('cid', 'title', 'slug', 'created')
            ->from($table)
            ->where('type = ?', 'post')
            ->where('status = ?', 'publish')
            ->where('created < ?', $article['created'])
            ->order('created', Db::SORT_DESC)
            ->limit(1);
        $prevArticle = $db->fetchRow($prevQuery);

        // 获取下一篇文章
        $nextQuery = $db->select('cid', 'title', 'slug', 'created')
            ->from($table)
            ->where('type = ?', 'post')
            ->where('status = ?', 'publish')
            ->where('created > ?', $article['created'])
            ->order('created', Db::SORT_ASC)
            ->limit(1);
        $nextArticle = $db->fetchRow($nextQuery);

        // 使用Typecho的路由系统生成文章链接
        $permalink = Router::url('post', $article, $this->options->siteUrl);

        // 提取文章内容中的外部链接（供小程序复制使用）
        $content = $this->convertContent($article['text']);
        $links = [];
        preg_match_all('/<a\s+[^>]*href\s*=\s*["\']([^"\']+)["\'][^>]*>(.*?)<\/a>/i', $content, $matches);
        if (!empty($matches[1])) {
            $seen = [];
            foreach ($matches[1] as $i => $href) {
                $href = html_entity_decode($href, ENT_QUOTES, 'UTF-8');
                if (isset($seen[$href])) continue;
                $seen[$href] = true;
                $text = trim(strip_tags($matches[2][$i]));
                $links[] = [
                    'href' => $href,
                    'text' => $text ?: $href
                ];
            }
        }

        // 组装返回数据
        $result = [
            'cid' => $article['cid'],
            'title' => $article['title'],
            'slug' => $article['slug'],
            'permalink' => $permalink,
            'content' => $content,
            'links' => $links,
            'created' => date('Y-m-d H:i:s', $article['created']),
            'modified' => date('Y-m-d H:i:s', $article['modified']),
            'author' => [
                'id' => $article['authorId'],
                'name' => $author['name'] ?? '',
                'screenName' => $author['screenName'] ?? '',
                'url' => $author['url'] ?? ''
            ],
            'tags' => array_map(function ($tag) {
                return ['name' => $tag['name'], 'slug' => $tag['slug']];
            }, $tags),
            'categories' => array_map(function ($cate) {
                return ['name' => $cate['name'], 'slug' => $cate['slug']];
            }, $categories),
            'allowComment' => (bool)$article['allowComment'],
            'allowPing' => (bool)$article['allowPing'],
            'allowFeed' => (bool)$article['allowFeed'],
            'commentsNum' => (int)$article['commentsNum'],
            'views' => (int)($article['views'] ?? 0),
            'agree' => (int)($article['agree'] ?? 0),
            'prev' => $prevArticle ? [
                'cid' => $prevArticle['cid'],
                'title' => $prevArticle['title'],
                'slug' => $prevArticle['slug'],
                'created' => date('Y-m-d H:i:s', $prevArticle['created'])
            ] : '没有啦',
            'next' => $nextArticle ? [
                'cid' => $nextArticle['cid'],
                'title' => $nextArticle['title'],
                'slug' => $nextArticle['slug'],
                'created' => date('Y-m-d H:i:s', $nextArticle['created'])
            ] : '没有啦',
            'random_image' => $this->getRandomImage(),
            'comments' => array_map(function ($comment) {
                return [
                    'coid' => $comment['coid'],
                    'author' => $comment['author'],
                    'content' => $this->convertContent($comment['text']),
                    'created' => date('Y-m-d H:i:s', $comment['created'])
                ];
            }, $comments)
        ];

        $this->sendResponse($result);
    }
    
    /**
     * 文章点赞/取消点赞
     * 
     * @access private
     * @return void
     */
    private function articleAgree()
    {
        if (!$this->hasColumn('agree')) {
            throw new \Exception('当前网站未安装点赞插件，agree 字段不可用', 501);
        }

        $db = Db::get();
        $prefix = $db->getPrefix();
        $table = $prefix . 'contents';
        $cid = intval($this->request->get('cid', 0));
        $type = $this->request->get('type', 'agree');
        
        if (empty($cid)) {
            throw new \Exception('文章CID不能为空');
        }
        
        // 验证文章存在且已发布
        $article = $db->fetchRow($db->select('cid', 'agree')
            ->from($table)
            ->where('cid = ?', $cid)
            ->where('type = ?', 'post')
            ->where('status = ?', 'publish'));
        
        if (empty($article)) {
            throw new \Exception('文章不存在或未发布');
        }
        
        $update = $db->update($table)->where('cid = ?', $cid);
        if ($type === 'cancel') {
            if ((int)$article['agree'] > 0) {
                $update->expression('agree', 'agree - 1');
            }
        } else {
            $update->expression('agree', 'agree + 1');
        }
        $db->query($update);
        
        $updated = $db->fetchRow($db->select('agree')->from($table)->where('cid = ?', $cid));
        
        $this->sendResponse([
            'cid' => $cid,
            'agree' => (int)$updated['agree']
        ]);
    }
    
    /**
     * 搜索文章
     * 
     * @access private
     * @return void
     */
    private function searchPosts()
    {
        $db = Db::get();
        $prefix = $db->getPrefix();
        $table = $prefix . 'contents';
        $keyword = trim($this->request->get('keyword', ''));
        if (empty($keyword)) {
            throw new \Exception('搜索关键词不能为空');
        }
        $page = max(1, intval($this->request->get('page', 1)));
        $pageSize = max(1, min(100, intval($this->request->get('pageSize', 10))));
        $offset = ($page - 1) * $pageSize;
        $searchTerm = '%' . str_replace(['%', '_'], ['\%', '\_'], $keyword) . '%';

        // 获取通过标签匹配的文章ID
        $tagQuery = $db->select('cid')
            ->from($prefix . 'metas')
            ->join($prefix . 'relationships', $prefix . 'metas.mid = ' . $prefix . 'relationships.mid')
            ->where('type = ?', 'tag')
            ->where('name LIKE ?', $searchTerm);
        
        $tagPosts = $db->fetchAll($tagQuery);
        $tagPostIds = array_column($tagPosts, 'cid');
        
        $postQuery = $db->select(
            'cid',
            'title',
            'slug',
            'created',
            'authorId',
            'text'
        )->from($table)
          ->where('type = ?', 'post')
          ->where('status = ?', 'publish');
        
        if (!empty($tagPostIds)) {
            $postQuery->where('(title LIKE ? OR text LIKE ? OR cid IN ?)', $searchTerm, $searchTerm, $tagPostIds);
        } else {
            $postQuery->where('(title LIKE ? OR text LIKE ?)', $searchTerm, $searchTerm);
        }
            
        $postQuery->order('created', Db::SORT_DESC)
            ->limit($pageSize)
            ->offset($offset);

        $articles = $db->fetchAll($postQuery);
        
        // 获取总数量
        $totalQuery = $db->select(['COUNT(*)' => 'num'])
            ->from($table)
            ->where('type = ?', 'post')
            ->where('status = ?', 'publish');
            
        if (!empty($tagPostIds)) {
            $totalQuery->where('(title LIKE ? OR text LIKE ? OR cid IN ?)', $searchTerm, $searchTerm, $tagPostIds);
        } else {
            $totalQuery->where('(title LIKE ? OR text LIKE ?)', $searchTerm, $searchTerm);
        }
        
        $total = $db->fetchObject($totalQuery)->num;

        $result = [];
        foreach ($articles as $article) {
            $tagQuery = $db->select('name')
                ->from($prefix . 'metas')
                ->join($prefix . 'relationships', $prefix . 'relationships.mid = ' . $prefix . 'metas.mid')
                ->where($prefix . 'relationships.cid = ?', $article['cid'])
                ->where('type = ?', 'tag');
            $tags = $db->fetchAll($tagQuery);

            $highlightTitle = str_ireplace(
                $keyword,
                "<span class=\"highlight\">{$keyword}</span>",
                $article['title']
            );

            $summary = mb_substr(strip_tags($this->convertContent($article['text'])), 0, 200) . '...';
            $highlightSummary = preg_replace(
                "/$keyword/i",
                "<span class=\"highlight\">$0</span>",
                $summary
            );

            $result[] = [
                'cid' => $article['cid'],
                'title' => $article['title'],
                'highlight_title' => $highlightTitle,
                'slug' => $article['slug'],
                'created' => date('Y-m-d H:i:s', $article['created']),
                'authorId' => $article['authorId'],
                'tags' => array_column($tags, 'name'),
                'summary' => $summary,
                'highlight_summary' => $highlightSummary
            ];
        }

        $this->sendResponse([
            'keyword' => $keyword,
            'data' => $result,
            'pagination' => [
                'total' => $total,
                'page' => $page,
                'pageSize' => $pageSize,
                'totalPages' => ceil($total / $pageSize)
            ]
        ]);
    }
    
    /**
     * 获取所有标签
     * 
     * @access private
     * @return void
     */
    private function getAllTags()
    {
        $db = Db::get();
        $prefix = $db->getPrefix();
        
        $query = $db->select('name', 'slug')
            ->from($prefix . 'metas')
            ->where('type = ?', 'tag')
            ->order('name', Db::SORT_ASC);

        $tags = $db->fetchAll($query);

        if (empty($tags)) {
            $this->sendResponse([]);
            return;
        }

        $result = [];
        foreach ($tags as $tag) {
            $result[] = [
                'name' => $tag['name'],
                'slug' => $tag['slug']
            ];
        }

        $this->sendResponse($result);
    }
    
    /**
     * 获取随机图片
     * 
     * @access private
     * @return string 随机图片完整URL，无图片则返回空字符串
     */
    private function getRandomImage()
    {
        $imageDir = 'usr/uploads/img/';
        $imagePath = '';

        if (is_dir($imageDir)) {
            $images = glob($imageDir . '*.jpg');

            if (!empty($images)) {
                $randomImage = $images[array_rand($images)];
                $siteUrl = rtrim($this->options->siteUrl, '/');
                $imagePath = $siteUrl . '/' . ltrim($randomImage, '/');
            }
        }

        return $imagePath;
    }

    // ============================================================
    // 以下为增强写操作：创建 / 更新 / 删除文章、上传媒体
    // 供 Hexo 博客管理 App 发布文章使用（POST，表单参数）
    // ============================================================

    /**
     * 创建/发布文章
     *
     * 参数（POST form 或 GET 均可）：
     *   title    文章标题（必填）
     *   text     正文（Markdown 或 HTML，必填）
     *   slug     缩略名（可选，默认由标题生成）
     *   status   发布状态（publish/draft/hidden/private/waiting，默认 publish）
     *   tags     标签，多个用英文逗号分隔
     *   category 分类，多个用英文逗号分隔（可选，为空则不指定）
     *   created  创建时间（unix 时间戳或 Y-m-d H:i:s，可选，默认当前时间）
     *
     * @access private
     * @return void
     */
    private function createPost()
    {
        $title = trim($this->request->get('title', ''));
        $text = $this->request->get('text', '');
        if (empty($title)) {
            throw new \Exception('文章标题不能为空', 400);
        }
        if ($text === '') {
            $text = '';
        }

        $db = Db::get();
        $prefix = $db->getPrefix();
        $table = $prefix . 'contents';

        // 状态校验
        $status = $this->request->get('status', 'publish');
        if (!in_array($status, ['publish', 'draft', 'hidden', 'private', 'waiting'])) {
            $status = 'publish';
        }

        // slug 生成与唯一化
        $slug = trim($this->request->get('slug', ''));
        if (empty($slug)) {
            $slug = $this->generateSlug($title);
        }
        $slug = $this->uniqueSlug($slug);

        // 创建时间
        $now = time();
        $createdRaw = $this->request->get('created', '');
        $created = $now;
        if (!empty($createdRaw)) {
            if (is_numeric($createdRaw)) {
                $created = intval($createdRaw);
            } else {
                $parsed = strtotime($createdRaw);
                if ($parsed !== false) {
                    $created = $parsed;
                }
            }
        }

        // Markdown 标记处理：非 HTML 内容补上 Typecho 的 markdown 标记
        $text = $this->normalizeContent($text);

        $insert = $db->insert($table)->rows([
            'title' => $title,
            'slug' => $slug,
            'created' => $created,
            'modified' => $now,
            'text' => $text,
            'order' => 0,
            'authorId' => 1,
            'template' => '',
            'type' => 'post',
            'status' => $status,
            'password' => '',
            'commentsNum' => 0,
            'allowComment' => 1,
            'allowPing' => 1,
            'allowFeed' => 1,
            'parent' => 0,
        ]);
        $cid = $db->query($insert);
        if (!$cid) {
            throw new \Exception('文章创建失败', 500);
        }

        // 处理标签与分类
        $this->setTags($cid, $this->request->get('tags', ''));
        $this->setCategories($cid, $this->request->get('category', ''));

        $row = [
            'cid' => $cid,
            'slug' => $slug,
            'created' => $created,
            'type' => 'post',
        ];
        $permalink = Router::url('post', $row, $this->options->siteUrl);

        $this->sendResponse([
            'id' => $cid,
            'cid' => $cid,
            'title' => $title,
            'slug' => $slug,
            'status' => $status,
            'permalink' => $permalink,
            'created' => date('Y-m-d H:i:s', $created),
            'modified' => date('Y-m-d H:i:s', $now),
        ]);
    }

    /**
     * 更新文章
     *
     * 参数：cid 必填；其余字段为空表示不修改。
     *   cid      文章 ID（必填）
     *   title / text / slug / status / tags / category
     *
     * @access private
     * @return void
     */
    private function updatePost()
    {
        $cid = intval($this->request->get('cid', 0));
        if (empty($cid)) {
            throw new \Exception('文章CID不能为空', 400);
        }

        $db = Db::get();
        $prefix = $db->getPrefix();
        $table = $prefix . 'contents';

        $article = $db->fetchRow($db->select()
            ->from($table)
            ->where('cid = ?', $cid)
            ->where('type = ?', 'post'));
        if (empty($article)) {
            throw new \Exception('文章不存在', 404);
        }

        $rows = [];
        $title = trim($this->request->get('title', ''));
        if ($title !== '') {
            $rows['title'] = $title;
        }
        $text = $this->request->get('text');
        if ($text !== null) {
            $rows['text'] = $this->normalizeContent($text);
        }
        $status = $this->request->get('status', '');
        if (in_array($status, ['publish', 'draft', 'hidden', 'private', 'waiting'])) {
            $rows['status'] = $status;
        }
        $slug = trim($this->request->get('slug', ''));
        if ($slug !== '') {
            $rows['slug'] = $this->uniqueSlug($slug, $cid);
        }
        $rows['modified'] = time();

        if (!empty($rows)) {
            $db->query($db->update($table)->rows($rows)->where('cid = ?', $cid));
        }

        // 更新标签（参数存在即全量替换）
        if ($this->request->get('tags') !== null) {
            $this->clearTaxonomy($cid, 'tag');
            $this->setTags($cid, $this->request->get('tags', ''));
        }
        // 更新分类（参数存在即全量替换）
        if ($this->request->get('category') !== null) {
            $this->clearTaxonomy($cid, 'category');
            $this->setCategories($cid, $this->request->get('category', ''));
        }

        $updated = $db->fetchRow($db->select()
            ->from($table)
            ->where('cid = ?', $cid));
        $permalink = Router::url('post', $updated, $this->options->siteUrl);

        $this->sendResponse([
            'id' => $cid,
            'cid' => $cid,
            'title' => $updated['title'],
            'slug' => $updated['slug'],
            'status' => $updated['status'],
            'permalink' => $permalink,
            'modified' => date('Y-m-d H:i:s', $updated['modified']),
        ]);
    }

    /**
     * 删除文章
     *
     * 参数：cid 必填
     *
     * @access private
     * @return void
     */
    private function deletePost()
    {
        $cid = intval($this->request->get('cid', 0));
        if (empty($cid)) {
            throw new \Exception('文章CID不能为空', 400);
        }

        $db = Db::get();
        $prefix = $db->getPrefix();
        $table = $prefix . 'contents';

        $article = $db->fetchRow($db->select('cid')
            ->from($table)
            ->where('cid = ?', $cid)
            ->where('type = ?', 'post'));
        if (empty($article)) {
            throw new \Exception('文章不存在', 404);
        }

        // 递减分类/标签计数
        $this->clearTaxonomy($cid, 'tag');
        $this->clearTaxonomy($cid, 'category');
        // 删除关联
        $db->query($db->delete($prefix . 'relationships')->where('cid = ?', $cid));
        $db->query($db->delete($prefix . 'comments')->where('cid = ?', $cid));
        // 删除文章
        $db->query($db->delete($table)->where('cid = ?', $cid));

        $this->sendResponse([
            'id' => $cid,
            'cid' => $cid,
            'deleted' => true
        ]);
    }

    /**
     * 上传媒体文件（multipart/form-data）
     *
     * 文件字段名：file
     * 保存到 usr/uploads/ 目录，返回可访问 URL。
     *
     * @access private
     * @return void
     */
    private function uploadMedia()
    {
        if (empty($_FILES) || empty($_FILES['file'])) {
            throw new \Exception('未接收到上传文件（字段名应为 file）', 400);
        }

        $file = $_FILES['file'];
        if (isset($file['error']) && $file['error'] !== UPLOAD_ERR_OK) {
            throw new \Exception('文件上传失败，错误码: ' . $file['error'], 400);
        }
        if ($file['size'] > 20 * 1024 * 1024) {
            throw new \Exception('文件大小超过限制（20MB）', 400);
        }

        // 校验扩展名
        $ext = strtolower(pathinfo($file['name'], PATHINFO_EXTENSION));
        $allowed = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'svg', 'bmp', 'ico',
                    'mp4', 'mp3', 'ogg', 'webm', 'pdf', 'zip', 'rar', '7z',
                    'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'md'];
        if (!in_array($ext, $allowed)) {
            throw new \Exception('不支持的文件类型: .' . $ext, 400);
        }

        $uploadRoot = __TYPECHO_ROOT_DIR__ . '/usr/uploads/';
        $relPath = date('Y/m') . '/' . uniqid() . '.' . $ext;
        $dest = $uploadRoot . $relPath;

        if (!is_dir(dirname($dest))) {
            @mkdir(dirname($dest), 0755, true);
        }

        if (!move_uploaded_file($file['tmp_name'], $dest)) {
            throw new \Exception('文件保存失败，请检查 usr/uploads 目录权限', 500);
        }

        $url = rtrim($this->options->siteUrl, '/') . '/usr/uploads/' . $relPath;

        $this->sendResponse([
            'id' => 0,
            'url' => $url,
            'name' => $file['name'],
            'size' => (int)$file['size'],
        ]);
    }

    // ── 写操作辅助方法 ──

    /**
     * 内容规范化：HTML 原样保存，非 HTML（Markdown）补上 Typecho 的 markdown 标记
     *
     * @access private
     * @param string $text 原始内容
     * @return string
     */
    private function normalizeContent($text)
    {
        if (empty($text)) {
            return '';
        }
        $text = str_replace('<!--markdown-->', '', $text);
        $trimmed = ltrim($text);
        if (preg_match('/^<([a-z][a-z0-9]*)\b[^>]*>/i', $trimmed)) {
            return $text;
        }
        return '<!--markdown-->' . $text;
    }

    /**
     * 从标题生成 URL 缩略名
     *
     * @access private
     * @param string $title 标题
     * @return string
     */
    private function generateSlug($title)
    {
        $slug = strtolower(trim($title));
        // 仅保留字母数字与连接符
        $slug = preg_replace('/[^a-z0-9]+/', '-', $slug);
        $slug = trim($slug, '-');
        if (empty($slug)) {
            $slug = date('YmdHis');
        }
        return $slug;
    }

    /**
     * 生成唯一 slug（追加后缀避免冲突）
     *
     * @access private
     * @param string $slug 期望的 slug
     * @param int $excludeCid 排除的文章 ID
     * @return string
     */
    private function uniqueSlug($slug, $excludeCid = 0)
    {
        $db = Db::get();
        $prefix = $db->getPrefix();
        $base = $slug;
        $i = 1;
        while (true) {
            $query = $db->select('cid')
                ->from($prefix . 'contents')
                ->where('slug = ?', $slug);
            if ($excludeCid > 0) {
                $query->where('cid <> ?', $excludeCid);
            }
            $exist = $db->fetchRow($query);
            if (empty($exist)) {
                return $slug;
            }
            $i++;
            $slug = $base . '-' . $i;
        }
    }

    /**
     * 为文章设置标签（标签不存在则自动创建）
     *
     * @access private
     * @param int $cid 文章 ID
     * @param string $tags 逗号分隔的标签
     * @return void
     */
    private function setTags($cid, $tags)
    {
        $this->attachTaxonomy($cid, 'tag', $tags);
    }

    /**
     * 为文章设置分类（分类不存在则自动创建为顶级分类）
     *
     * @access private
     * @param int $cid 文章 ID
     * @param string $categories 逗号分隔的分类
     * @return void
     */
    private function setCategories($cid, $categories)
    {
        $this->attachTaxonomy($cid, 'category', $categories);
    }

    /**
     * 关联文章与分类/标签（自动创建不存在的元数据并维护计数）
     *
     * @access private
     * @param int $cid 文章 ID
     * @param string $type tag / category
     * @param string $raw 逗号分隔的名称列表
     * @return void
     */
    private function attachTaxonomy($cid, $type, $raw)
    {
        $names = array_filter(array_map('trim', explode(',', trim($raw))));
        if (empty($names)) {
            return;
        }
        $db = Db::get();
        $prefix = $db->getPrefix();

        foreach ($names as $name) {
            $meta = $db->fetchRow($db->select('mid')
                ->from($prefix . 'metas')
                ->where('type = ?', $type)
                ->where('name = ?', $name));
            if (empty($meta)) {
                $mid = $db->query($db->insert($prefix . 'metas')->rows([
                    'name' => $name,
                    'slug' => $this->uniqueMetaSlug($name, $type),
                    'type' => $type,
                    'description' => '',
                    'count' => 1,
                    'order' => 0,
                    'parent' => 0,
                ]));
            } else {
                $mid = $meta['mid'];
                $db->query($db->update($prefix . 'metas')
                    ->expression('count', 'count + 1')
                    ->where('mid = ?', $mid));
            }
            // 避免重复关联
            $rel = $db->fetchRow($db->select('cid')
                ->from($prefix . 'relationships')
                ->where('cid = ?', $cid)
                ->where('mid = ?', $mid));
            if (empty($rel)) {
                $db->query($db->insert($prefix . 'relationships')->rows([
                    'cid' => $cid,
                    'mid' => $mid,
                ]));
            }
        }
    }

    /**
     * 清除文章指定类型（tag/category）的全部关联并递减计数
     *
     * @access private
     * @param int $cid 文章 ID
     * @param string $type tag / category
     * @return void
     */
    private function clearTaxonomy($cid, $type)
    {
        $db = Db::get();
        $prefix = $db->getPrefix();

        $rels = $db->fetchAll($db->select('mid', 'type')
            ->from($prefix . 'relationships')
            ->where('cid = ?', $cid));
        if (empty($rels)) {
            return;
        }
        foreach ($rels as $rel) {
            $meta = $db->fetchRow($db->select('type')
                ->from($prefix . 'metas')
                ->where('mid = ?', $rel['mid']));
            if ($meta && $meta['type'] === $type) {
                $countObj = $db->fetchObject($db->select('count')
                    ->from($prefix . 'metas')
                    ->where('mid = ?', $rel['mid']));
                $newCount = max(0, (int)($countObj->count ?? 0) - 1);
                $db->query($db->update($prefix . 'metas')
                    ->rows(['count' => $newCount])
                    ->where('mid = ?', $rel['mid']));
                $db->query($db->delete($prefix . 'relationships')
                    ->where('cid = ?', $cid)
                    ->where('mid = ?', $rel['mid']));
            }
        }
    }

    /**
     * 生成唯一的分类/标签 slug
     *
     * @access private
     * @param string $name 名称
     * @param string $type tag / category
     * @return string
     */
    private function uniqueMetaSlug($name, $type)
    {
        $base = $this->generateSlug($name);
        $slug = $base;
        $i = 1;
        while (true) {
            $db = Db::get();
            $prefix = $db->getPrefix();
            $row = $db->fetchRow($db->select('mid')
                ->from($prefix . 'metas')
                ->where('type = ?', $type)
                ->where('slug = ?', $slug));
            if (empty($row)) {
                return $slug;
            }
            $i++;
            $slug = $base . '-' . $i;
        }
    }
    
    /**
     * 发送成功响应
     * 
     * @access private
     * @param mixed $data 响应数据
     * @return void
     */
    private function sendResponse($data)
    {
        echo json_encode([
            'success' => true,
            'data' => $data
        ], JSON_UNESCAPED_UNICODE);
        exit;
    }
    
    /**
     * 发送错误响应
     * 
     * @access private
     * @param string $message 错误消息
     * @param int $code 错误代码
     * @return void
     */
    private function sendError($message, $code = 500)
    {
        http_response_code($code);
        echo json_encode([
            'success' => false,
            'error' => [
                'message' => $message,
                'code' => $code
            ]
        ], JSON_UNESCAPED_UNICODE);
        exit;
    }
    
    /**
     * 将文章内容从 Markdown 转换为 HTML
     * 如果内容已包含 HTML 标签则直接返回，否则调用 Typecho 内置 Markdown 解析器
     * 
     * @access private
     * @param string $text 原始内容
     * @return string
     */
    private function convertContent($text)
    {
        if (empty($text)) {
            return '';
        }
        
        // 移除 Typecho 的 markdown 标记
        $text = str_replace('<!--markdown-->', '', $text);
        
        // 如果内容明显已经是 HTML（以标签开头），直接返回
        $trimmed = ltrim($text);
        if (preg_match('/^<([a-z][a-z0-9]*)\b[^>]*>/i', $trimmed)) {
            return $text;
        }
        
        // 使用 Typecho 内置的 Markdown 解析器
        return Markdown::convert($text);
    }
}
