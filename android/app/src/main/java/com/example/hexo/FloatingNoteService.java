package com.example.hexo;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.graphics.PixelFormat;
import android.graphics.Point;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.provider.Settings;

import java.io.File;
import android.text.InputType;
import android.view.Gravity;
import android.view.LayoutInflater;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.view.inputmethod.InputMethodManager;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.ImageButton;
import android.widget.TextView;
import android.widget.Toast;

/**
 * 悬浮速记窗服务（复刻 QuickDaily FloatingNoteService）：
 * 通过 WindowManager + TYPE_APPLICATION_OVERLAY 创建系统级悬浮窗，
 * 完全独立于 Flutter 引擎，点击小部件/磁贴只弹出速记窗，不打开主界面。
 *
 * 动作：
 * - ACTION_SHOW     显示悬浮窗（携带 source / prefill / target）
 * - ACTION_HIDE     隐藏悬浮窗
 * - ACTION_REFRESH  从草稿恢复内容
 */
public class FloatingNoteService extends Service {

    public static final String ACTION_SHOW = "com.example.hexo.action.SHOW_FLOATING_NOTE";
    public static final String ACTION_HIDE = "com.example.hexo.action.HIDE_FLOATING_NOTE";
    public static final String ACTION_REFRESH = "com.example.hexo.action.REFRESH_FLOATING_NOTE";

    public static final String EXTRA_SOURCE = "source";
    public static final String EXTRA_PREFILL = "prefill";
    public static final String EXTRA_TARGET = "target";

    private static final String CHANNEL_ID = "floating_note";
    private static final int NOTIF_ID = 1;

    private WindowManager mWindowManager;
    private View mOverlayView;
    private EditText mInput;
    private TextView mTitle;
    private FrameLayout mRoot;

    private boolean mDragging = false;
    private float mTouchStartX;
    private float mTouchStartY;
    private int mStartX;
    private int mStartY;
    private int mDragMode;
    private static final int DRAG_NONE = 0;
    private static final int DRAG_MOVE = 1;

    private WindowManager.LayoutParams mParams;
    private final Handler mMainHandler = new Handler(Looper.getMainLooper());

    private String mPendingSource = "";
    private String mPendingPrefill = "";

    // ── 动作入口 ──

    public static Intent showIntent(Context context, String source, String prefill) {
        Intent intent = new Intent(context, FloatingNoteService.class);
        intent.setAction(ACTION_SHOW);
        if (source != null) intent.putExtra(EXTRA_SOURCE, source);
        if (prefill != null) intent.putExtra(EXTRA_PREFILL, prefill);
        return intent;
    }

    public static Intent hideIntent(Context context) {
        return new Intent(context, FloatingNoteService.class).setAction(ACTION_HIDE);
    }

    /** 是否具备悬浮窗权限 */
    public static boolean canDrawOverlays(Context context) {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.M
                || Settings.canDrawOverlays(context);
    }

    @Override
    public void onCreate() {
        super.onCreate();
        mWindowManager = (WindowManager) getSystemService(WINDOW_SERVICE);
        startForegroundCompat();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent == null) {
            return START_STICKY;
        }
        String action = intent.getAction();
        if (ACTION_SHOW.equals(action)) {
            mPendingSource = intent.getStringExtra(EXTRA_SOURCE) == null ? "" : intent.getStringExtra(EXTRA_SOURCE);
            mPendingPrefill = intent.getStringExtra(EXTRA_PREFILL) == null ? "" : intent.getStringExtra(EXTRA_PREFILL);
            showOverlay();
        } else if (ACTION_HIDE.equals(action)) {
            hideOverlay();
        } else if (ACTION_REFRESH.equals(action)) {
            if (mInput != null) {
                String draft = NativeQuickNoteStore.loadDraftText(this);
                mInput.setText(draft);
                int sel = NativeQuickNoteStore.loadDraftSelection(this);
                if (sel > draft.length()) sel = draft.length();
                mInput.setSelection(sel);
            }
        }
        return START_STICKY;
    }

    // ── 悬浮窗生命周期 ──

    private void showOverlay() {
        if (mOverlayView != null) {
            mWindowManager.updateViewLayout(mOverlayView, mParams);
            return;
        }
        if (!canDrawOverlays(this)) {
            openOverlaySettings();
            return;
        }

        LayoutInflater inflater = (LayoutInflater) getSystemService(LAYOUT_INFLATER_SERVICE);
        mOverlayView = inflater.inflate(R.layout.floating_note_view, null);
        mRoot = mOverlayView.findViewById(R.id.floating_note_root);
        mInput = mOverlayView.findViewById(R.id.floating_input);
        mTitle = mOverlayView.findViewById(R.id.floating_title);
        View titleBar = mOverlayView.findViewById(R.id.floating_title_bar);
        ImageButton saveBtn = mOverlayView.findViewById(R.id.floating_save_btn);
        ImageButton closeBtn = mOverlayView.findViewById(R.id.floating_close_btn);
        ImageButton toolTimestamp = mOverlayView.findViewById(R.id.floating_tool_timestamp);
        ImageButton toolBold = mOverlayView.findViewById(R.id.floating_tool_bold);
        ImageButton toolList = mOverlayView.findViewById(R.id.floating_tool_list);
        View saveTextBtn = mOverlayView.findViewById(R.id.floating_save_text_btn);

        if (!mPendingPrefill.isEmpty()) {
            mInput.setText(mPendingPrefill);
        } else {
            String draft = NativeQuickNoteStore.loadDraftText(this);
            mInput.setText(draft);
            int sel = NativeQuickNoteStore.loadDraftSelection(this);
            if (sel > draft.length()) sel = draft.length();
            mInput.setSelection(sel);
        }

        // 尺寸：88% 屏宽，35% 屏高
        Point size = new Point();
        mWindowManager.getDefaultDisplay().getSize(size);
        int width = (int) (size.x * 0.88f);
        int height = (int) (size.y * 0.35f);
        int minHeight = dp(280);
        int minWidth = dp(260);
        if (height < minHeight) height = minHeight;
        if (width < minWidth) width = minWidth;

        // 位置：记忆或居中偏上
        int savedX = getSharedPreferences("floating_note_pos", MODE_PRIVATE).getInt("x", -1);
        int savedY = getSharedPreferences("floating_note_pos", MODE_PRIVATE).getInt("y", -1);
        int x = savedX >= 0 ? savedX : (size.x - width) / 2;
        int y = savedY >= 0 ? savedY : (int) (size.y * 0.2f);

        mParams = new WindowManager.LayoutParams(
                width,
                height,
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                        ? WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                        : WindowManager.LayoutParams.TYPE_PHONE,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                        | WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH
                        | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                PixelFormat.TRANSLUCENT);
        mParams.gravity = Gravity.TOP | Gravity.START;
        mParams.x = x;
        mParams.y = y;
        mParams.windowAnimations = android.R.style.Animation_InputMethod;

        setupInputFocus(mInput);
        setupTitleDrag(titleBar);
        setupButtons(saveBtn, closeBtn, toolTimestamp, toolBold, toolList, saveTextBtn);
        mOverlayView.setOnTouchListener(new View.OnTouchListener() {
            @Override
            public boolean onTouch(View v, MotionEvent event) {
                return false;
            }
        });

        try {
            mWindowManager.addView(mOverlayView, mParams);
        } catch (Exception e) {
            Toast.makeText(this, "无法显示悬浮窗", Toast.LENGTH_SHORT).show();
            mOverlayView = null;
            return;
        }

        // 延迟请求焦点以弹出键盘
        mMainHandler.postDelayed(new Runnable() {
            @Override
            public void run() {
                if (mOverlayView != null) {
                    mParams.flags &= ~WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE;
                    mWindowManager.updateViewLayout(mOverlayView, mParams);
                    mInput.requestFocus();
                    InputMethodManager imm = (InputMethodManager) getSystemService(INPUT_METHOD_SERVICE);
                    imm.showSoftInput(mInput, InputMethodManager.SHOW_IMPLICIT);
                }
            }
        }, 150);
    }

    private void setupInputFocus(EditText input) {
        input.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_MULTI_LINE);
        input.setOnFocusChangeListener(new View.OnFocusChangeListener() {
            @Override
            public void onFocusChange(View v, boolean hasFocus) {
                if (hasFocus && mParams != null) {
                    mParams.flags &= ~WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE;
                    if (mOverlayView != null) {
                        mWindowManager.updateViewLayout(mOverlayView, mParams);
                    }
                }
            }
        });
    }

    private void setupTitleDrag(final View titleBar) {
        titleBar.setOnTouchListener(new View.OnTouchListener() {
            @Override
            public boolean onTouch(View v, MotionEvent event) {
                switch (event.getActionMasked()) {
                    case MotionEvent.ACTION_DOWN:
                        mDragging = true;
                        mTouchStartX = event.getRawX();
                        mTouchStartY = event.getRawY();
                        mStartX = mParams.x;
                        mStartY = mParams.y;
                        return true;
                    case MotionEvent.ACTION_MOVE:
                        if (mDragging && mParams != null) {
                            mParams.x = mStartX + (int) (event.getRawX() - mTouchStartX);
                            mParams.y = mStartY + (int) (event.getRawY() - mTouchStartY);
                            mWindowManager.updateViewLayout(mOverlayView, mParams);
                        }
                        return true;
                    case MotionEvent.ACTION_UP:
                    case MotionEvent.ACTION_CANCEL:
                        if (mDragging) {
                            mDragging = false;
                            getSharedPreferences("floating_note_pos", MODE_PRIVATE)
                                    .edit()
                                    .putInt("x", mParams.x)
                                    .putInt("y", mParams.y)
                                    .apply();
                        }
                        return true;
                }
                return false;
            }
        });
    }

    private void setupButtons(ImageButton saveBtn, ImageButton closeBtn,
                              ImageButton toolTimestamp, ImageButton toolBold,
                              ImageButton toolList, View saveTextBtn) {
        saveBtn.setOnClickListener(v -> saveAndHide());
        closeBtn.setOnClickListener(v -> hideOverlay());
        saveTextBtn.setOnClickListener(v -> saveAndHide());

        toolTimestamp.setOnClickListener(v -> insertTimestamp());
        toolBold.setOnClickListener(v -> wrapSelection("**"));
        toolList.setOnClickListener(v -> {
            int start = mInput.getSelectionStart();
            int end = mInput.getSelectionEnd();
            String text = mInput.getText().toString();
            if (start < 0) start = text.length();
            String prefix = "- ";
            if (isTaskListLine(text, start)) {
                prefix = "";
            }
            mInput.getText().replace(Math.min(start, end), Math.max(start, end), "");
            mInput.getText().insert(Math.min(start, end), prefix);
            mInput.setSelection(Math.min(start, end) + prefix.length());
        });
    }

    private boolean isTaskListLine(String text, int index) {
        int lineStart = text.lastIndexOf('\n', index - 1) + 1;
        return text.regionMatches(lineStart, "- ", 0, 2);
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

    private void saveAndHide() {
        String text = mInput == null ? "" : mInput.getText().toString();
        if (text.trim().isEmpty()) {
            Toast.makeText(this, "内容为空", Toast.LENGTH_SHORT).show();
            return;
        }
        File saved = NativeQuickNoteStore.saveToMd(this, null, "datetime", true, text);
        if (saved != null) {
            Toast.makeText(this, "已保存", Toast.LENGTH_SHORT).show();
            // 回显到速记小部件：保存成功后刷新，小部件显示最新速记文字
            QuickNoteWidgetProvider.refreshAll(this);
        } else {
            Toast.makeText(this, "保存失败", Toast.LENGTH_SHORT).show();
        }
        hideOverlay();
    }

    private void hideOverlay() {
        if (mOverlayView != null) {
            // 保存草稿到 SharedPreferences，防内容丢失
            String text = mInput == null ? "" : mInput.getText().toString();
            if (!text.trim().isEmpty()) {
                NativeQuickNoteStore.persistDraft(this, text, mInput.getSelectionStart());
            } else {
                NativeQuickNoteStore.clearDraft(this);
            }
            try {
                mWindowManager.removeView(mOverlayView);
            } catch (Exception ignored) {
            }
            mOverlayView = null;
            mInput = null;
        }
        stopForegroundCompat();
    }

    private void openOverlaySettings() {
        Intent intent = new Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:" + getPackageName()));
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        try {
            startActivity(intent);
        } catch (Exception e) {
            Toast.makeText(this, "请在系统设置中开启悬浮窗权限", Toast.LENGTH_LONG).show();
        }
    }

    // ── 前台服务保活 ──

    private void startForegroundCompat() {
        NotificationManager nm = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = new NotificationChannel(CHANNEL_ID, "速记悬浮窗",
                    NotificationManager.IMPORTANCE_LOW);
            channel.setDescription("悬浮速记窗运行提示");
            nm.createNotificationChannel(channel);
        }
        Notification.Builder b = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                ? new Notification.Builder(this, CHANNEL_ID)
                : new Notification.Builder(this);
        b.setContentTitle("拓墨速记")
                .setContentText("悬浮速记窗正在运行")
                .setSmallIcon(R.drawable.ic_add_dark)
                .setOngoing(true);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            startForeground(NOTIF_ID, b.build());
        }
    }

    private void stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE);
        } else {
            stopForeground(true);
        }
    }

    @Override
    public void onDestroy() {
        if (mOverlayView != null) {
            try {
                mWindowManager.removeView(mOverlayView);
            } catch (Exception ignored) {
            }
            mOverlayView = null;
        }
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    private int dp(int value) {
        return (int) (value * getResources().getDisplayMetrics().density + 0.5f);
    }
}
