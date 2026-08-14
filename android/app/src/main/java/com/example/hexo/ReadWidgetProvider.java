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
    public static final String ACTION_TOGGLE_TASK = "com.example.hexo.action.READ_TOGGLE_TASK";

    public static final String PREFS = "read_widget";
    public static final String KEY_TASK_MODE = "task_mode";

    public static final String EXTRA_TASK_PATH = "task_path";
    public static final String EXTRA_TASK_LINE = "task_line";

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
        } else if (ACTION_TOGGLE_TASK.equals(intent.getAction())) {
            String path = intent.getStringExtra(EXTRA_TASK_PATH);
            int line = intent.getIntExtra(EXTRA_TASK_LINE, -1);
            if (path != null && !path.isEmpty() && line >= 0) {
                final PendingResult pendingResult = goAsync();
                new Thread(() -> {
                    try {
                        java.io.File f = new java.io.File(path);
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

        // 任务视图下点击行 → 勾选切换（由本 Provider 处理并刷新自身，保证界面即时更新）
        Intent toggleIntent = new Intent(context, ReadWidgetProvider.class)
                .setAction(ACTION_TOGGLE_TASK);
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

        // 编辑：打开当前文章（携带路径，Flutter 打开编辑器）
        String articlePath = NativeQuickNoteStore.getSelectedArticlePath(context, "read");
        Intent editIntent = QuickNoteIntent.build(context,
                QuickNoteIntent.MODE_OPEN_ARTICLE, null, articlePath);
        views.setOnClickPendingIntent(
                R.id.btn_home,
                PendingIntent.getActivity(
                        context,
                        appWidgetId + 100,
                        editIntent,
                        PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE));

        // 选文：打开文章选择器（Flutter 弹出选择页，选中后回写路径并刷新）
        Intent pickIntent = QuickNoteIntent.build(context,
                QuickNoteIntent.MODE_PICK_ARTICLE, null, null);
        views.setOnClickPendingIntent(
                R.id.btn_pick,
                PendingIntent.getActivity(
                        context,
                        appWidgetId + 200,
                        pickIntent,
                        PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE));

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
