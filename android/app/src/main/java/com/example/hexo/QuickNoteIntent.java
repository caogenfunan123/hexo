package com.example.hexo;

import android.content.Context;
import android.content.Intent;
import android.net.Uri;

/**
 * 速记入口工具：统一构建「从桌面小部件 / 快捷磁贴拉起编辑器」的 Intent。
 *
 * 与 Flutter 侧约定 extra：
 *   quick_note_mode   : "new"（新建草稿，直达编辑器）
 *   quick_note_text   : 可选，预填的速记文本（如磁贴磁贴输入）
 *   quick_note_path   : 可选，文章文件绝对路径（open_article 模式打开指定文章）
 */
public final class QuickNoteIntent {
    public static final String EXTRA_MODE = "quick_note_mode";
    public static final String EXTRA_TEXT = "quick_note_text";
    public static final String EXTRA_PATH = "quick_note_path";
    public static final String MODE_NEW = "new";
    public static final String MODE_OPEN_ARTICLE = "open_article";
    public static final String MODE_PICK_ARTICLE = "pick_article";

    private QuickNoteIntent() {
    }

    /** 拉起主界面并进入新建草稿（桌面小部件 / 磁贴共用） */
    public static Intent build(Context context, String mode, String text) {
        return build(context, mode, text, null);
    }

    /** 拉起主界面：新建草稿 / 打开指定文章 / 打开文章选择器 */
    public static Intent build(Context context, String mode, String text, String path) {
        Intent intent = new Intent(context, MainActivity.class);
        // 修复：不再使用 ACTION_MAIN + CATEGORY_LAUNCHER。
        // 带 MAIN/LAUNCHER 的 intent 与点桌面图标的启动 intent 等效，MIUI/HyperOS 等
        // ROM 会把"已运行应用的等效启动"判定为切回前台并丢弃 extras，导致热启动时
        // 小部件深链只打开主界面（参数丢失）。
        // 现在改用唯一 scheme 的 data，让每次深链都是"新意图"强制投递；
        // 显式 component intent 无需在 Manifest 添加 intent-filter 即可携带 data。
        final String m = mode == null ? MODE_NEW : mode;
        intent.setData(Uri.parse("hexo://quicknote/" + m
                + "?path=" + Uri.encode(path == null ? "" : path)
                + "&text=" + Uri.encode(text == null ? "" : text)));
        intent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP
                | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        intent.putExtra(EXTRA_MODE, m);
        if (text != null && !text.isEmpty()) {
            intent.putExtra(EXTRA_TEXT, text);
        }
        if (path != null && !path.isEmpty()) {
            intent.putExtra(EXTRA_PATH, path);
        }
        return intent;
    }
}
