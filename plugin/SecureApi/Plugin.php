<?php
namespace TypechoPlugin\SecureApi;

use Typecho\Plugin\PluginInterface;
use Typecho\Widget\Helper\Form;
use Typecho\Widget\Helper\Form\Element\Radio;
use Typecho\Widget\Helper\Form\Element\Text;
use Typecho\Db;
use Utils\Helper;
use Typecho\Common;

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
if (!defined('__TYPECHO_ROOT_DIR__')) exit;
require_once __DIR__ . '/Action.php';

/**
 * 专为 Typecho 1.3.0 版本打造，完美兼容 PHP8.0 环境，
 * 集成了带密钥验证机制的数据接口与后台密钥综合管理功能。
 *
 * 增强版：在官方 SecureApi 只读接口基础上，新增文章发布/更新/删除
 * 与媒体上传接口（createPost / updatePost / deletePost / uploadMedia），
 * 供 Hexo 博客管理 App 直接发布文章。
 * 
 * @package 小程序API接口
 * @author 笨小猪
 * @version 1.2.0
 * @link https://gitee.com/nice_ch/typecho-plugin
 */
class Plugin implements PluginInterface
{
    /**
     * 激活插件方法
     * 
     * @access public
     * @return string
     * @throws \Typecho\Plugin\Exception
     */
    public static function activate()
    {
        // 注册路由
        Helper::addRoute('secureApi', '/api', __NAMESPACE__ . '\Action', 'action');
        
        // 注册后台侧边栏菜单
        \Typecho\Plugin::factory('admin/menu.php')->navBar = __CLASS__ . '::renderMenu';
        
        // 获取数据库连接
        $db = Db::get();
        $prefix = $db->getPrefix();
        
        // Typecho 1.3.0 统一使用 json 格式存储配置
        $encode = 'json_encode';
        
        // 检查并设置默认密钥
        $config = self::getConfig();
        if (empty($config)) {
            $apiKey = self::generateRandomKey();
            // 插入新配置
            $db->query($db->insert($prefix . 'options')
                ->rows([
                    'name' => 'plugin:SecureApi',
                    'value' => $encode(['apiKey' => $apiKey, 'apiEnabled' => '0']),
                    'user' => 0
                ]));
        } elseif (empty($config['apiKey'])) {
            $apiKey = self::generateRandomKey();
            $config['apiKey'] = $apiKey;
            if (!isset($config['apiEnabled'])) {
                $config['apiEnabled'] = '0';
            }
            // 更新现有配置
            $db->query($db->update($prefix . 'options')
                ->rows(['value' => $encode($config)])
                ->where('name = ?', 'plugin:SecureApi'));
        }
        
        return '插件激活成功，请在设置中修改默认密钥';
    }
    
    /**
     * 禁用插件方法
     * 
     * @access public
     * @return string
     */
    public static function deactivate()
    {
        Helper::removeRoute('secureApi');
        return '插件已禁用';
    }
    
    /**
     * 获取插件配置面板
     * 
     * @access public
     * @param Form $form 配置表单
     * @return void
     */
    public static function config(Form $form)
    {
        // 强制获取当前配置
        $currentConfig = self::getConfig();
        // API开关
        $options = \Widget\Options::alloc();
        $siteUrl = rtrim($options->siteUrl, '/');
        $token = !empty($currentConfig['apiKey']) ? $currentConfig['apiKey'] : '你的密钥';
        $isRewrite = !empty($options->rewrite);
        $apiPath = $isRewrite ? "$siteUrl/api" : "$siteUrl/index.php/api";
        $apiHelp = sprintf(
            '当前Typecho程序版本：%s<br>'
            . '控制API的开启与关闭，只有开启后API才能正常使用。<br>'
            . '%s<br>请求示例：%s?token=%s&action=getWebInfo',
            Common::VERSION,
            $isRewrite ? '✅ 已开启地址重写（伪静态）' : '⚠ 未开启地址重写，使用普通模式',
            $apiPath, $token
        );
        $apiEnabled = new Radio('apiEnabled', 
            array('0' => '关闭', '1' => '开启'), 
            $currentConfig['apiEnabled'] ?? '0', 
            _t('API开关'), _t($apiHelp));
        $form->addInput($apiEnabled);
        // API密钥配置项
        $apiKey = new Text('apiKey', NULL, 
            $currentConfig['apiKey'] ?? '', 
            _t('API 密钥'), _t('请设置包含字母和数字的安全密钥，长度不能少于8位'));
        
        // 修复验证规则
        $form->addInput($apiKey->addRule('required', _t('密钥不能为空'))
            ->addRule('minLength', _t('密钥长度不能少于8位'), 8));
            
        // 隐藏空分类开关（用于绕过微信审核）
        $hideEmptyCategories = new Radio('hideEmptyCategories', 
            array('0' => '关闭', '1' => '开启'), 
            $currentConfig['hideEmptyCategories'] ?? '0', 
            _t('隐藏空分类'), _t('开启后，getCategories接口将自动隐藏整个子树（父/子/孙）文章数均为零的分类。<br>适用于微信小程序审核期间隐藏敏感分类内容。'));
        $form->addInput($hideEmptyCategories);

        // 小程序分享配置项
        $shareConfig = new Text('shareConfig', NULL,
            $currentConfig['shareConfig'] ?? '', 
            _t('小程序分享配置'), _t('格式：图片URL|转发给朋友的分享语|分享到朋友圈的分享语<br>例如：http://xxx.com/xxx.png|分享到好友|分享到朋友圈<br>站内图片可使用相对路径，如：/xxx.png'));
        $form->addInput($shareConfig);

    }
    
    /**
     * 个人配置面板
     * 
     * @access public
     * @param Form $form 个人配置表单
     * @return void
     */
    public static function personalConfig(Form $form)
    {
         // 空实现，不添加任何个人配置项，不然会报错
    }
    
    /**
     * 渲染后台侧边栏菜单
     * 
     * @access public
     * @static
     * @return void
     */
    public static function renderMenu()
    {
        echo '<a href="options-plugin.php?config=SecureApi">API接口管理</a>';
    }

    /**
     * 生成随机密钥
     * 
     * @access private
     * @return string
     */
    private static function generateRandomKey()
    {
        $chars = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
        $key = '';
        $charsLength = strlen($chars) - 1;
        for ($i = 0; $i < 32; $i++) {
            $key .= $chars[random_int(0, $charsLength)];
        }
        return $key;
    }
    
    /**
     * 安全获取配置 - 公共静态方法
     * 1.3.0 版本统一使用 JSON 格式存储
     * 
     * @access public
     * @static
     * @return array
     */
    public static function getConfig()
    {
        try {
            $db = Db::get();
            $prefix = $db->getPrefix();
            
            // 从数据库直接获取配置（1.3.0 统一 JSON 格式）
            $row = $db->fetchRow($db->select('value')
                ->from($prefix . 'options')
                ->where('name = ?', 'plugin:SecureApi'));
                
            if ($row && !empty($row['value'])) {
                $data = json_decode($row['value'], true);
                if (is_array($data)) {
                    return $data;
                }
                return [];
            }
            
            return [];
        } catch (\Exception $e) {
            return [];
        }
    }
}
