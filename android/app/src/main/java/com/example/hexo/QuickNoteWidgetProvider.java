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
 * 点击任意区域 → 拉起 MainActivity 并直达速记（带 QuickNoteIntent.EXTRA_MODE），
 * Flutter 侧自动聚焦输入框弹出键盘，输入后自动保存。
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

        // 整块点击 → 直达速记
        Intent intent = QuickNoteIntent.build(context, QuickNoteIntent.MODE_NEW, null);
        PendingIntent pi = PendingIntent.getActivity(
                context,
                appWidgetId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        views.setOnClickPendingIntent(R.id.widget_root, pi);

        appWidgetManager.updateAppWidget(appWidgetId, views);
    }
}
