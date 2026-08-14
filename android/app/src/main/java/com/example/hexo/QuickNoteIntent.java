package com.example.hexo;

import android.content.Context;
import android.content.Intent;

/**
 * 速记入口工具：统一构建「从桌面小部件 / 快捷磁贴拉起编辑器」的 Intent。
 *
 * 与 Flutter 侧约定 extra：
 *   quick_note_mode   : "new"（新建草稿，直达编辑器）
 *   quick_note_text   : 可选，预填的速记文本（如磁贴磁贴输入）
 */
public final class QuickNoteIntent {
    public static final String EXTRA_MODE = "quick_note_mode";
    public static final String EXTRA_TEXT = "quick_note_text";
    public static final String MODE_NEW = "new";

    private QuickNoteIntent() {
    }

    /** 拉起主界面并进入新建草稿（桌面小部件 / 磁贴共用） */
    public static Intent build(Context context, String mode, String text) {
        Intent intent = new Intent(context, MainActivity.class);
        intent.setAction(Intent.ACTION_MAIN);
        intent.addCategory(Intent.CATEGORY_LAUNCHER);
        intent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP
                | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        intent.putExtra(EXTRA_MODE, mode == null ? MODE_NEW : mode);
        if (text != null && !text.isEmpty()) {
            intent.putExtra(EXTRA_TEXT, text);
        }
        return intent;
    }
}
