package com.example.hexo;

import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.net.Uri;
import android.widget.RemoteViews;

/**
 * 阅读小部件：展示最新速记草稿内容。
 *
 * 眼睛按钮在「原文视图」与「任务视图」之间切换（SharedPreferences 记忆）；
 * 主页按钮拉起主应用编辑该速记。
 */
public class ReadWidgetProvider extends AppWidgetProvider {

    public static final String ACTION_TOGGLE_MODE = "com.example.hexo.action.READ_TOGGLE_MODE";

    public static final String PREFS = "read_widget";
    public static final String KEY_TASK_MODE = "task_mode";

    @Override
    public void onUpdate(Context context, AppWidgetManager appWidgetManager, int[] appWidgetIds) {
        for (int appWidgetId : appWidgetIds) {
            updateWidget(context, appWidgetManager, appWidgetId);
        }
    }

    @Override
    public void onReceive(Context context, Intent intent) {
        super.onReceive(context, intent);
        if (ACTION_TOGGLE_MODE.equals(intent.getAction())) {
            SharedPreferences prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
            boolean current = prefs.getBoolean(KEY_TASK_MODE, false);
            prefs.edit().putBoolean(KEY_TASK_MODE, !current).apply();
            refreshAll(context);
        }
    }

    /** 刷新所有阅读小部件 */
    public static void refreshAll(Context context) {
        try {
            AppWidgetManager manager = AppWidgetManager.getInstance(context);
            int[] ids = manager.getAppWidgetIds(
                    new android.content.ComponentName(context, ReadWidgetProvider.class));
            for (int id : ids) {
                updateWidget(context, manager, id);
            }
        } catch (Exception ignored) {
        }
    }

    private static void updateWidget(Context context, AppWidgetManager appWidgetManager, int appWidgetId) {
        RemoteViews views = new RemoteViews(context.getPackageName(), R.layout.widget_diary_read);

        Intent serviceIntent = new Intent(context, ReadWidgetViewsService.class);
        serviceIntent.setData(Uri.parse("hexo://read-widget/" + appWidgetId));
        serviceIntent.putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId);
        views.setRemoteAdapter(R.id.content_list, serviceIntent);
        views.setEmptyView(R.id.content_list, R.id.empty_view);

        // 任务视图下点击行 → 勾选切换
        Intent toggleIntent = new Intent(context, TaskWidgetProvider.class)
                .setAction(TaskWidgetProvider.ACTION_TOGGLE_TASK);
        views.setPendingIntentTemplate(
                R.id.content_list,
                PendingIntent.getBroadcast(
                        context,
                        appWidgetId + 400,
                        toggleIntent,
                        PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_MUTABLE));

        // 眼睛：切换 原文/任务 视图
        Intent modeIntent = new Intent(context, ReadWidgetProvider.class).setAction(ACTION_TOGGLE_MODE);
        views.setOnClickPendingIntent(
                R.id.btn_eye,
                PendingIntent.getBroadcast(
                        context,
                        appWidgetId + 300,
                        modeIntent,
                        PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE));

        // 主页：打开主应用
        Intent homeIntent = new Intent(context, MainActivity.class);
        homeIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        views.setOnClickPendingIntent(
                R.id.btn_home,
                PendingIntent.getActivity(
                        context,
                        appWidgetId + 100,
                        homeIntent,
                        PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE));

        appWidgetManager.updateAppWidget(appWidgetId, views);
    }
}
