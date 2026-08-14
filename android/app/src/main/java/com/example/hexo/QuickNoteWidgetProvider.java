package com.example.hexo;

import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.widget.RemoteViews;

/**
 * 桌面小部件：一键速记。
 *
 * 复刻 QuickDaily 极简设计：白色圆角卡片 + 居中加号；有速记时回显最近一次输入的文字。
 * 点击任意区域 → 启动 FloatingNoteService 弹出原生悬浮速记窗，
 * 只出速记窗、不打开主界面（除非缺少悬浮窗权限）。
 */
public class QuickNoteWidgetProvider extends AppWidgetProvider {

    public static final String ACTION_REFRESH = "com.example.hexo.ACTION_QUICK_NOTE_REFRESH";

    @Override
    public void onUpdate(Context context, AppWidgetManager appWidgetManager, int[] appWidgetIds) {
        for (int appWidgetId : appWidgetIds) {
            updateWidget(context, appWidgetManager, appWidgetId);
        }
    }

    @Override
    public void onReceive(Context context, Intent intent) {
        super.onReceive(context, intent);
        if (ACTION_REFRESH.equals(intent.getAction())) {
            refreshAll(context);
        }
    }

    /** 刷新所有速记小部件（保存速记后调用，回显最新文字） */
    public static void refreshAll(Context context) {
        try {
            AppWidgetManager manager = AppWidgetManager.getInstance(context);
            int[] ids = manager.getAppWidgetIds(
                    new ComponentName(context, QuickNoteWidgetProvider.class));
            for (int id : ids) {
                updateWidget(context, manager, id);
            }
        } catch (Exception ignored) {
        }
    }

    private static void updateWidget(Context context, AppWidgetManager appWidgetManager, int appWidgetId) {
        RemoteViews views = new RemoteViews(context.getPackageName(), R.layout.widget_quick_note);

        // 整块点击 → 透明中转 Activity（QuickNoteLauncherActivity）：
        // 由它统一处理悬浮窗权限检查 + startForegroundService 启动悬浮速记窗，
        // 然后立即 finish，屏幕只闪现透明页、不会打开主界面。
        // 相比直接 getForegroundService，中转 Activity 属于前台启动，
        // 规避 Android 12+ 及部分厂商 ROM 从 AppWidget 后台启动 FGS 被拦截的问题。
        Intent launcherIntent = new Intent(context, QuickNoteLauncherActivity.class)
                .putExtra(FloatingNoteService.EXTRA_SOURCE, "widget")
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        PendingIntent pi = PendingIntent.getActivity(
                context,
                appWidgetId,
                launcherIntent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        views.setOnClickPendingIntent(R.id.widget_root, pi);

        // 回显最近一次速记文字；无则显示加号空态
        String text = NativeQuickNoteStore.latestDraftText(context);
        if (text != null && !text.trim().isEmpty()) {
            views.setTextViewText(R.id.widget_text, text);
            views.setViewVisibility(R.id.widget_text, android.view.View.VISIBLE);
            views.setViewVisibility(R.id.widget_empty_state, android.view.View.GONE);
        } else {
            views.setTextViewText(R.id.widget_text, "");
            views.setViewVisibility(R.id.widget_text, android.view.View.GONE);
            views.setViewVisibility(R.id.widget_empty_state, android.view.View.VISIBLE);
        }

        appWidgetManager.updateAppWidget(appWidgetId, views);
    }
}
