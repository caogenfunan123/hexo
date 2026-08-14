package com.example.hexo;

import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.content.Intent;
import android.widget.RemoteViews;
import android.widget.RemoteViewsService;

import java.io.File;
import java.util.List;

/**
 * 任务小部件列表数据源：解析最新速记草稿 md 的任务行渲染为列表项。
 */
public class TaskWidgetViewsService extends RemoteViewsService {

    @Override
    public RemoteViewsFactory onGetViewFactory(Intent intent) {
        return new TaskViewsFactory(intent);
    }

    private static class TaskViewsFactory implements RemoteViewsFactory {

        private List<TaskWidgetTaskParser.TaskItem> mTasks;
        private final int mAppWidgetId;

        TaskViewsFactory(Intent intent) {
            mAppWidgetId = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID,
                    AppWidgetManager.INVALID_APPWIDGET_ID);
        }

        @Override
        public void onCreate() {
        }

        @Override
        public void onDataSetChanged() {
            String path = NativeQuickNoteStore.latestDraftPath(TaskWidgetViewsService.this);
            String content = "";
            if (path != null && !path.isEmpty()) {
                content = TaskWidgetTaskParser.readFile(new File(path));
                if (content == null) content = "";
            }
            mTasks = TaskWidgetTaskParser.parse(content);
        }

        @Override
        public void onDestroy() {
            mTasks = null;
        }

        @Override
        public int getCount() {
            return mTasks == null ? 0 : mTasks.size();
        }

        @Override
        public RemoteViews getViewAt(int position) {
            if (mTasks == null || position >= mTasks.size()) return null;
            TaskWidgetTaskParser.TaskItem item = mTasks.get(position);
            RemoteViews views = new RemoteViews(getPackageName(), R.layout.widget_task_item);
            views.setTextViewText(R.id.task_text, item.text);
            views.setImageViewResource(R.id.task_checkbox,
                    item.checked
                            ? android.R.drawable.checkbox_on_background
                            : android.R.drawable.checkbox_off_background);

            // 点击勾选：携带路径与行号
            Intent fillIntent = new Intent();
            fillIntent.putExtra(TaskWidgetProvider.EXTRA_TASK_PATH,
                    NativeQuickNoteStore.latestDraftPath(TaskWidgetViewsService.this));
            fillIntent.putExtra(TaskWidgetProvider.EXTRA_TASK_LINE, item.lineIndex);
            views.setOnClickFillInIntent(R.id.task_checkbox, fillIntent);
            views.setOnClickFillInIntent(R.id.task_row, fillIntent);
            return views;
        }

        @Override
        public RemoteViews getLoadingView() {
            return null;
        }

        @Override
        public int getViewTypeCount() {
            return 1;
        }

        @Override
        public long getItemId(int position) {
            return position;
        }

        @Override
        public boolean hasStableIds() {
            return false;
        }
    }
}
