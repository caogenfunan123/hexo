package com.example.hexo;

import android.content.Context;
import android.content.Intent;
import android.widget.RemoteViews;
import android.widget.RemoteViewsService;

import java.io.File;
import java.util.ArrayList;
import java.util.List;

/**
 * 阅读小部件列表数据源：读取最新速记草稿 md。
 *
 * - 任务视图：只渲染任务行，点击可勾选
 * - 原文视图：逐行渲染全文（简化：保留 markdown 前缀原文）
 */
public class ReadWidgetViewsService extends RemoteViewsService {

    @Override
    public RemoteViewsFactory onGetViewFactory(Intent intent) {
        return new ReadViewsFactory(this);
    }

    private static class ReadViewsFactory implements RemoteViewsFactory {

        private final Context mContext;
        private List<String> mLines = new ArrayList<>();
        private boolean mTaskMode;
        private String mLatestPath = "";

        ReadViewsFactory(Context context) {
            mContext = context;
        }

        @Override
        public void onCreate() {
        }

        @Override
        public void onDataSetChanged() {
            mTaskMode = mContext.getSharedPreferences(ReadWidgetProvider.PREFS, Context.MODE_PRIVATE)
                    .getBoolean(ReadWidgetProvider.KEY_TASK_MODE, false);
            mLatestPath = NativeQuickNoteStore.latestDraftPath(mContext);
            String content = "";
            if (!mLatestPath.isEmpty()) {
                content = TaskWidgetTaskParser.readFile(new File(mLatestPath));
                if (content == null) content = "";
            }
            if (mTaskMode) {
                List<TaskWidgetTaskParser.TaskItem> tasks = TaskWidgetTaskParser.parse(content);
                mLines = new ArrayList<>();
                for (TaskWidgetTaskParser.TaskItem t : tasks) {
                    mLines.add(t.text);
                }
            } else {
                mLines = new ArrayList<>();
                for (String line : content.split("\n", -1)) {
                    if (line.trim().isEmpty()) continue;
                    mLines.add(line);
                }
            }
        }

        @Override
        public void onDestroy() {
            mLines = null;
        }

        @Override
        public int getCount() {
            return mLines == null ? 0 : mLines.size();
        }

        @Override
        public RemoteViews getViewAt(int position) {
            if (mLines == null || position >= mLines.size()) return null;
            RemoteViews views = new RemoteViews(mContext.getPackageName(), R.layout.widget_diary_read_line);
            String line = mLines.get(position);
            views.setTextViewText(R.id.read_line_text, line);

            // 任务视图：点击整行切换勾选状态
            if (mTaskMode) {
                Intent fillIntent = new Intent();
                fillIntent.putExtra(TaskWidgetProvider.EXTRA_TASK_PATH, mLatestPath);
                fillIntent.putExtra(TaskWidgetProvider.EXTRA_TASK_LINE, position);
                views.setOnClickFillInIntent(R.id.read_line_text, fillIntent);
            }
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
