package com.example.hexo;

import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.widget.RemoteViews;

import java.io.File;
import java.util.List;

/**
 * 任务小部件：展示最新速记草稿中的待办事项（- [ ] / - [x]），点击勾选切换。
 *
 * 数据源：MD文章/ 目录下最新一篇未导入速记草稿 md（与 Flutter 导入共用的约定）。
 */
public class TaskWidgetProvider extends AppWidgetProvider {

    public static final String ACTION_TOGGLE_TASK = "com.example.hexo.action.TOGGLE_TASK";
    public static final String ACTION_REFRESH = "com.example.hexo.action.REFRESH_TASKS";

    public static final String EXTRA_TASK_PATH = "task_path";
    public static final String EXTRA_TASK_LINE = "task_line";
    public static final String EXTRA_TASK_RAW = "task_raw";

    private static final int INVALID_WIDGET_ID = -1;

    @Override
    public void onUpdate(Context context, AppWidgetManager appWidgetManager, int[] appWidgetIds) {
        for (int appWidgetId : appWidgetIds) {
            updateWidget(context, appWidgetManager, appWidgetId);
        }
    }

    @Override
    public void onReceive(Context context, Intent intent) {
        super.onReceive(context, intent);
        String action = intent.getAction();
        if (ACTION_TOGGLE_TASK.equals(action)) {
            String path = intent.getStringExtra(EXTRA_TASK_PATH);
            int line = intent.getIntExtra(EXTRA_TASK_LINE, -1);
            if (path != null && line >= 0) {
                final PendingResult pendingResult = goAsync();
                new Thread(() -> {
                    try {
                        File f = new File(path);
                        String content = TaskWidgetTaskParser.readFile(f);
                        if (content != null) {
                            String toggled = TaskWidgetTaskParser.toggleLine(content, line);
                            if (toggled != null) {
                                TaskWidgetTaskParser.writeFile(f, toggled);
                            }
                        }
                    } catch (Exception ignored) {
                    } finally {
                        refreshAll(context);
                        pendingResult.finish();
                    }
                }).start();
            }
        } else if (ACTION_REFRESH.equals(action)) {
            refreshAll(context);
        }
    }

    /** 刷新所有任务小部件 */
    public static void refreshAll(Context context) {
        try {
            AppWidgetManager manager = AppWidgetManager.getInstance(context);
            int[] ids = manager.getAppWidgetIds(
                    new android.content.ComponentName(context, TaskWidgetProvider.class));
            for (int id : ids) {
                updateWidget(context, manager, id);
            }
        } catch (Exception ignored) {
        }
    }

    private static void updateWidget(Context context, AppWidgetManager appWidgetManager, int appWidgetId) {
        RemoteViews views = new RemoteViews(context.getPackageName(), R.layout.widget_tasks);

        // 任务列表：RemoteViewsService 渲染
        Intent serviceIntent = new Intent(context, TaskWidgetViewsService.class);
        serviceIntent.setData(Uri.parse("hexo://task-widget/" + appWidgetId));
        serviceIntent.putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId);
        views.setRemoteAdapter(R.id.task_list, serviceIntent);

        // 空态
        views.setEmptyView(R.id.task_list, R.id.empty_view);

        // 刷新按钮
        Intent refreshIntent = new Intent(context, TaskWidgetProvider.class).setAction(ACTION_REFRESH);
        views.setOnClickPendingIntent(
                R.id.btn_refresh,
                PendingIntent.getBroadcast(
                        context,
                        appWidgetId + 200,
                        refreshIntent,
                        PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE));

        // 选文按钮：打开文章选择器（选中后回写路径并刷新）
        Intent pickIntent = QuickNoteIntent.build(context,
                QuickNoteIntent.MODE_PICK_ARTICLE, null, null);
        views.setOnClickPendingIntent(
                R.id.btn_pick,
                PendingIntent.getActivity(
                        context,
                        appWidgetId + 300,
                        pickIntent,
                        PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE));

        // 列表项点击模板 → 勾选切换
        Intent toggleIntent = new Intent(context, TaskWidgetProvider.class).setAction(ACTION_TOGGLE_TASK);
        views.setPendingIntentTemplate(
                R.id.task_list,
                PendingIntent.getBroadcast(
                        context,
                        appWidgetId + 100,
                        toggleIntent,
                        PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_MUTABLE));

        // 整块空白点击 → 弹悬浮速记窗（与速记小部件行为一致）
        // 列表行 / 按钮各自已有 PendingIntent，空白区域才落到根布局
        Intent quickNoteIntent = new Intent(context, QuickNoteLauncherActivity.class)
                .putExtra(FloatingNoteService.EXTRA_SOURCE, "widget")
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        views.setOnClickPendingIntent(
                R.id.widget_root,
                PendingIntent.getActivity(
                        context,
                        appWidgetId + 500,
                        quickNoteIntent,
                        PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE));

        appWidgetManager.updateAppWidget(appWidgetId, views);
    }
}
