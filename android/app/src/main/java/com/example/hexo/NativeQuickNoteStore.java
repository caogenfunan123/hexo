package com.example.hexo;

import android.content.Context;
import android.content.SharedPreferences;

import java.io.File;
import java.io.FileOutputStream;
import java.io.OutputStreamWriter;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.Date;
import java.util.List;
import java.util.Locale;

/**
 * 原生速记数据层：草稿持久化 + md 落盘。
 *
 * 与 Flutter 侧约定：
 * - 草稿 md 写入 {@code <filesDir>/MD文章/} 目录（与 Flutter StorageService.mdArticlesDir 一致）
 * - 文件名 {@code <epochMillis>_<title>.md}，UTF-8，无 frontmatter
 * - 导入完成后在 md 旁写 {@code <basename>.md.imported} 标记，Flutter 扫描时跳过
 * - 时间戳格式与 Flutter TimestampFormat 各 key 对齐
 */
public final class NativeQuickNoteStore {

    private static final String PREFS = "native_quick_note";
    private static final String KEY_DRAFT_TEXT = "draft_text";
    private static final String KEY_DRAFT_SELECTION = "draft_selection";
    private static final String KEY_TARGET = "draft_target";
    private static final String MD_DIR = "MD文章";
    private static final String IMPORTED_SUFFIX = ".imported";

    private NativeQuickNoteStore() {
    }

    // ── 目录 ──

    /** 草稿 md 目录：<filesDir>/MD文章 */
    public static File mdDir(Context context) {
        File dir = new File(context.getFilesDir(), MD_DIR);
        if (!dir.exists()) {
            dir.mkdirs();
        }
        return dir;
    }

    // ── 草稿持久化（SharedPreferences，防进程杀丢失） ──

    public static String loadDraftText(Context context) {
        return prefs(context).getString(KEY_DRAFT_TEXT, "");
    }

    public static int loadDraftSelection(Context context) {
        return prefs(context).getInt(KEY_DRAFT_SELECTION, 0);
    }

    public static String loadTarget(Context context) {
        return prefs(context).getString(KEY_TARGET, "");
    }

    public static void persistDraft(Context context, String text, int selection) {
        prefs(context).edit()
                .putString(KEY_DRAFT_TEXT, text == null ? "" : text)
                .putInt(KEY_DRAFT_SELECTION, selection)
                .apply();
    }

    public static void clearDraft(Context context) {
        prefs(context).edit()
                .remove(KEY_DRAFT_TEXT)
                .remove(KEY_DRAFT_SELECTION)
                .remove(KEY_TARGET)
                .apply();
    }

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    // ── md 落盘 ──

    /**
     * 将速记内容写入 md 文件。
     *
     * @param anchor            锚点文本（可为空）
     * @param timestampFormatKey 时间戳格式 key（date/time/datetime/iso/slash/cn/compact）
     * @param insertTimestamp   是否插入时间戳
     * @param text              用户输入正文
     * @return 写入的文件，失败返回 null
     */
    public static File saveToMd(Context context, String anchor, String timestampFormatKey,
                                boolean insertTimestamp, String text) {
        try {
            String title = extractTitle(text);
            String ts = insertTimestamp ? formatTimestamp(timestampFormatKey) : "";
            StringBuilder sb = new StringBuilder();
            if (anchor != null && !anchor.trim().isEmpty()) {
                sb.append(anchor);
                if (!anchor.endsWith("\n")) sb.append('\n');
            }
            if (insertTimestamp && !ts.isEmpty()) {
                sb.append(ts).append('\n');
            }
            if (text != null && !text.trim().isEmpty()) {
                sb.append(text.trim()).append('\n');
            }
            if (sb.length() == 0) {
                return null;
            }
            long epoch = System.currentTimeMillis();
            String safeTitle = sanitizeFileName(title);
            File out = new File(mdDir(context), epoch + "_" + safeTitle + ".md");
            writeUtf8(out, sb.toString());
            clearDraft(context);
            return out;
        } catch (Exception e) {
            android.util.Log.e("NativeQuickNote", "saveToMd failed: " + e.getMessage(), e);
            return null;
        }
    }

    /** 从文本提取标题：首行去 markdown 前缀，截断 40 字符，空则"速记" */
    public static String extractTitle(String text) {
        if (text == null) return "速记";
        String first = "";
        for (String line : text.split("\n")) {
            String t = line.trim();
            if (!t.isEmpty()) {
                first = t;
                break;
            }
        }
        first = first.replaceFirst("^#+\\s*", "")
                .replaceFirst("^[-*]\\s*", "")
                .replaceFirst("^>\\s*", "")
                .trim();
        if (first.isEmpty()) first = "速记";
        if (first.length() > 40) first = first.substring(0, 40) + "…";
        return first;
    }

    private static String sanitizeFileName(String name) {
        return name.replaceAll("[\\\\/:*?\"<>|\\s]+", "_");
    }

    private static void writeUtf8(File file, String content) throws Exception {
        try (OutputStreamWriter w = new OutputStreamWriter(
                new FileOutputStream(file), StandardCharsets.UTF_8)) {
            w.write(content);
            w.flush();
        }
    }

    private static String readUtf8(File file) {
        try {
            byte[] bytes = java.nio.file.Files.readAllBytes(file.toPath());
            return new String(bytes, StandardCharsets.UTF_8);
        } catch (Exception e) {
            android.util.Log.e("NativeQuickNote", "readUtf8 failed: " + e.getMessage());
            return null;
        }
    }

    // ── 时间戳（对齐 Flutter TimestampFormat） ──

    public static String formatTimestamp(String formatKey) {
        Date now = new Date();
        if (formatKey == null) formatKey = "date";
        switch (formatKey) {
            case "time":
                return new SimpleDateFormat("HH:mm", Locale.getDefault()).format(now);
            case "datetime":
                return new SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.getDefault()).format(now);
            case "iso":
                return new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.getDefault()).format(now);
            case "slash":
                return new SimpleDateFormat("yyyy/MM/dd HH:mm", Locale.getDefault()).format(now);
            case "cn": {
                // 2026年8月14日 14:30
                java.util.Calendar c = java.util.Calendar.getInstance();
                return c.get(java.util.Calendar.YEAR) + "年" + (c.get(java.util.Calendar.MONTH) + 1)
                        + "月" + c.get(java.util.Calendar.DAY_OF_MONTH) + "日 "
                        + new SimpleDateFormat("HH:mm", Locale.getDefault()).format(now);
            }
            case "compact":
                return new SimpleDateFormat("yyyyMMdd-HHmm", Locale.getDefault()).format(now);
            default:
                return new SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(now);
        }
    }

    // ── 待导入文件列表（Flutter 启动扫描） ──

    /** 列出 MD文章 目录中未被导入的 md 文件（按文件名时间戳倒序） */
    public static List<File> listUnimportedMd(Context context) {
        List<File> result = new ArrayList<>();
        File dir = mdDir(context);
        File[] files = dir.listFiles();
        if (files == null) return result;
        Arrays.sort(files, new Comparator<File>() {
            @Override
            public int compare(File a, File b) {
                return b.getName().compareTo(a.getName());
            }
        });
        for (File f : files) {
            if (f.isFile() && f.getName().endsWith(".md")
                    && !f.getName().endsWith(IMPORTED_SUFFIX)
                    && !new File(f.getAbsolutePath() + IMPORTED_SUFFIX).exists()) {
                result.add(f);
            }
        }
        return result;
    }

    /** 标记文件已导入 */
    public static void markImported(Context context, File mdFile) {
        try {
            File marker = new File(mdFile.getAbsolutePath() + IMPORTED_SUFFIX);
            if (!marker.exists()) {
                marker.createNewFile();
            }
        } catch (Exception e) {
            android.util.Log.e("NativeQuickNote", "markImported failed: " + e.getMessage());
        }
    }

    /** 全部已导入标记文件（供清理） */
    public static void clearAllImportedMarkers(Context context) {
        File dir = mdDir(context);
        File[] files = dir.listFiles();
        if (files == null) return;
        for (File f : files) {
            if (f.isFile() && f.getName().endsWith(IMPORTED_SUFFIX)) {
                f.delete();
            }
        }
    }

    // ── 任务小部件数据源 ──

    /** 最新一篇速记 md 的绝对路径，无则返回空串 */
    public static String latestDraftPath(Context context) {
        List<File> files = listUnimportedMd(context);
        if (files.isEmpty()) return "";
        return files.get(0).getAbsolutePath();
    }

    /**
     * 最新一篇速记的正文（首行起最多 200 字符，去除 markdown 前缀），无则返回空串。
     * 供速记小部件回显最近一次输入的速记文字。
     */
    public static String latestDraftText(Context context) {
        try {
            List<File> files = listUnimportedMd(context);
            if (files.isEmpty()) return "";
            String content = readUtf8(files.get(0));
            if (content == null) return "";
            StringBuilder sb = new StringBuilder();
            for (String line : content.split("\n")) {
                String t = line.trim();
                if (t.isEmpty()) continue;
                t = t.replaceFirst("^#+\\s*", "")
                        .replaceFirst("^[-*]\\s*", "")
                        .replaceFirst("^>\\s*", "")
                        .trim();
                if (t.isEmpty()) continue;
                sb.append(t).append(' ');
                if (sb.length() > 200) break;
            }
            return sb.toString().trim();
        } catch (Exception e) {
            android.util.Log.e("NativeQuickNote", "latestDraftText failed: " + e.getMessage());
            return "";
        }
    }

    // ── 小部件文章选择（阅读/任务小部件显示指定文章） ──

    private static final String KEY_READ_ARTICLE = "read_widget_article_path";
    private static final String KEY_TASK_ARTICLE = "task_widget_article_path";

    /** 保存小部件显示的文章路径；widget 为 read/task */
    public static boolean setSelectedArticlePath(Context context, String widget, String path) {
        try {
            prefs(context).edit()
                    .putString("read".equals(widget) ? KEY_READ_ARTICLE : KEY_TASK_ARTICLE,
                            path == null ? "" : path)
                    .apply();
            return true;
        } catch (Exception e) {
            android.util.Log.e("NativeQuickNote", "setSelectedArticlePath failed: " + e.getMessage());
            return false;
        }
    }

    /** 读取小部件显示的文章路径，未选择时回落到最新速记 */
    public static String getSelectedArticlePath(Context context, String widget) {
        String p = prefs(context).getString(
                "read".equals(widget) ? KEY_READ_ARTICLE : KEY_TASK_ARTICLE, "");
        if (p == null || p.isEmpty()) {
            return latestDraftPath(context);
        }
        File f = new File(p);
        if (!f.exists()) {
            return latestDraftPath(context);
        }
        return p;
    }

    /** 列出 MD文章 目录下全部 md 文件绝对路径（按名称倒序，供文章选择器） */
    public static List<String> listAllMdPaths(Context context) {
        List<String> result = new ArrayList<>();
        File dir = mdDir(context);
        File[] files = dir.listFiles();
        if (files == null) return result;
        Arrays.sort(files, new Comparator<File>() {
            @Override
            public int compare(File a, File b) {
                return b.getName().compareTo(a.getName());
            }
        });
        for (File f : files) {
            if (f.isFile() && f.getName().endsWith(".md")) {
                result.add(f.getAbsolutePath());
            }
        }
        return result;
    }
}
