package com.example.hexo;

import android.app.Activity;
import android.os.Bundle;
import android.util.Log;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.ImageButton;
import android.widget.Toast;

import java.io.File;

/**
 * 悬浮速记窗（透明 Activity 形式，复刻 QuickDaily NoteEditActivity）。
 *
 * 点击桌面小部件 / 磁贴时直接以透明 Activity 弹出悬浮速记卡片：
 * 全屏半透明遮罩 + 居中偏上输入卡片，点击遮罩关闭。
 *
 * 不需要 SYSTEM_ALERT_WINDOW 悬浮窗权限，也不依赖前台服务，
 * 彻底绕开国产 ROM（MIUI / HyperOS / ColorOS / EMUI）对
 * 系统悬浮窗和后台启动前台服务的拦截，兼容性最好。
 */
public class QuickNoteLauncherActivity extends Activity {

    private static final String TAG = "QuickNoteLauncher";

    private EditText mInput;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        Log.d(TAG, "onCreate show floating note edit window");

        setContentView(R.layout.note_edit_view);

        mInput = findViewById(R.id.note_input);
        View backdrop = findViewById(R.id.note_edit_backdrop);
        View card = findViewById(R.id.note_edit_card);

        // 悬浮卡片尺寸与位置：宽 88% 屏宽、高 35% 屏高，居中偏上
        int screenW = getResources().getDisplayMetrics().widthPixels;
        int screenH = getResources().getDisplayMetrics().heightPixels;
        FrameLayout.LayoutParams lp = (FrameLayout.LayoutParams) card.getLayoutParams();
        lp.width = (int) (screenW * 0.88f);
        lp.height = (int) (screenH * 0.35f);
        lp.gravity = Gravity.TOP | Gravity.CENTER_HORIZONTAL;
        lp.topMargin = (int) (screenH * 0.2f);
        card.setLayoutParams(lp);

        // 点击遮罩关闭（关闭时自动保存草稿）
        backdrop.setOnClickListener(v -> finish());

        ImageButton saveBtn = findViewById(R.id.note_save_btn);
        ImageButton closeBtn = findViewById(R.id.note_close_btn);
        Button saveTextBtn = findViewById(R.id.note_save_text_btn);
        ImageButton toolTs = findViewById(R.id.note_tool_ts);
        ImageButton toolBold = findViewById(R.id.note_tool_bold);
        ImageButton toolList = findViewById(R.id.note_tool_list);

        saveBtn.setOnClickListener(v -> saveAndFinish());
        saveTextBtn.setOnClickListener(v -> saveAndFinish());
        closeBtn.setOnClickListener(v -> finish());

        toolTs.setOnClickListener(v -> insertTimestamp());
        toolBold.setOnClickListener(v -> wrapSelection("**"));
        toolList.setOnClickListener(v -> toggleListPrefix());

        // 恢复草稿
        String draft = NativeQuickNoteStore.loadDraftText(this);
        mInput.setText(draft);
        int sel = NativeQuickNoteStore.loadDraftSelection(this);
        if (sel > draft.length()) sel = draft.length();
        mInput.setSelection(sel);

        // 自动聚焦弹出键盘
        mInput.requestFocus();
    }

    private void insertTimestamp() {
        String ts = NativeQuickNoteStore.formatTimestamp("datetime");
        int start = mInput.getSelectionStart();
        int end = mInput.getSelectionEnd();
        if (start < 0) start = mInput.length();
        mInput.getText().replace(start, Math.max(end, start), ts);
        mInput.setSelection(start + ts.length());
    }

    private void wrapSelection(String wrap) {
        int start = mInput.getSelectionStart();
        int end = mInput.getSelectionEnd();
        if (start < 0 || end < 0) return;
        String sel = mInput.getText().subSequence(Math.min(start, end), Math.max(start, end)).toString();
        mInput.getText().replace(start, end, wrap + sel + wrap);
    }

    private void toggleListPrefix() {
        int start = mInput.getSelectionStart();
        int end = mInput.getSelectionEnd();
        String text = mInput.getText().toString();
        if (start < 0) start = text.length();
        int pos = Math.min(start, Math.max(end, 0));
        String prefix = isTaskListLine(text, pos) ? "" : "- ";
        mInput.getText().replace(pos, Math.max(end, pos), prefix);
        mInput.setSelection(pos + prefix.length());
    }

    private boolean isTaskListLine(String text, int index) {
        int lineStart = text.lastIndexOf('\n', index - 1) + 1;
        return text.regionMatches(lineStart, "- ", 0, 2);
    }

    private void saveAndFinish() {
        String text = mInput == null ? "" : mInput.getText().toString();
        if (text.trim().isEmpty()) {
            Toast.makeText(this, "内容为空", Toast.LENGTH_SHORT).show();
            return;
        }
        File saved = NativeQuickNoteStore.saveToMd(this, null, "datetime", true, text);
        if (saved != null) {
            Toast.makeText(this, "已保存", Toast.LENGTH_SHORT).show();
            // 同步刷新所有桌面小部件
            QuickNoteWidgetProvider.refreshAll(this);
            TaskWidgetProvider.refreshAll(this);
            ReadWidgetProvider.refreshAll(this);
        } else {
            Toast.makeText(this, "保存失败", Toast.LENGTH_SHORT).show();
            return;
        }
        finish();
    }

    @Override
    public void finish() {
        // 关闭时保存草稿到 SharedPreferences，防止内容丢失
        if (mInput != null) {
            String text = mInput.getText().toString();
            if (!text.trim().isEmpty()) {
                NativeQuickNoteStore.persistDraft(this, text, mInput.getSelectionStart());
            } else {
                NativeQuickNoteStore.clearDraft(this);
            }
        }
        super.finish();
        overridePendingTransition(0, 0);
    }
}
