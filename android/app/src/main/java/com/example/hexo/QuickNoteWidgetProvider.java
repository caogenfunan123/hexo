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
 * 点击任意区域 → 拉起 MainActivity 并进入新建草稿（带 QuickNoteIntent.EXTRA_MODE）。
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

        // 整块点击 → 新建草稿
        Intent intent = QuickNoteIntent.build(context, QuickNoteIntent.MODE_NEW, null);
        PendingIntent pi = PendingIntent.getActivity(
                context,
                appWidgetId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        views.setOnClickPendingIntent(R.id.widget_root, pi);

        views.setTextViewText(R.id.widget_date, android.text.format.DateFormat.getDateFormat(context)
                .format(new java.util.Date()));

        appWidgetManager.updateAppWidget(appWidgetId, views);
    }
}
