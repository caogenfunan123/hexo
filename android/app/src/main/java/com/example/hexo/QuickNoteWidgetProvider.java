package com.example.hexo;

import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.Context;
import android.content.Intent;
import android.widget.RemoteViews;

/**
 * 桌面小部件：一键速记。
 *
 * 复刻 QuickDaily 极简设计：白色圆角卡片 + 居中加号。
 * 点击任意区域 → 启动 FloatingNoteService 弹出原生悬浮速记窗，
 * 只出速记窗、不打开主界面（除非缺少悬浮窗权限）。
 */
public class QuickNoteWidgetProvider extends AppWidgetProvider {

    @Override
    public void onUpdate(Context context, AppWidgetManager appWidgetManager, int[] appWidgetIds) {
        for (int appWidgetId : appWidgetIds) {
            updateWidget(context, appWidgetManager, appWidgetId);
        }
    }

    private void updateWidget(Context context, AppWidgetManager appWidgetManager, int appWidgetId) {
        RemoteViews views = new RemoteViews(context.getPackageName(), R.layout.widget_quick_note);

        // 整块点击 → 启动悬浮速记窗
        Intent serviceIntent = FloatingNoteService.showIntent(context, "widget", null);
        PendingIntent pi = PendingIntent.getService(
                context,
                appWidgetId,
                serviceIntent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        views.setOnClickPendingIntent(R.id.widget_root, pi);

        appWidgetManager.updateAppWidget(appWidgetId, views);
    }
}
