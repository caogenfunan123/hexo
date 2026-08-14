package com.example.hexo;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * 任务小部件数据模型与 markdown 任务行解析/切换工具。
 *
 * 任务行格式（与 Flutter 侧 markdown 任务列表一致）：
 * {@code - [ ] 任务描述}  /  {@code - [x] 任务描述}
 */
public final class TaskWidgetTaskParser {

    public static class TaskItem {
        public final String text;
        public final int lineIndex;
        public final boolean checked;

        public TaskItem(String text, int lineIndex, boolean checked) {
            this.text = text;
            this.lineIndex = lineIndex;
            this.checked = checked;
        }
    }

    private static final Pattern TASK_LINE =
            Pattern.compile("^([ \\t]*)[-+*]\\s*\\[\\s*([xX ])\\s*]\\s*(.*)$");

    private TaskWidgetTaskParser() {
    }

    /** 解析正文中的任务行 */
    public static List<TaskItem> parse(String content) {
        List<TaskItem> result = new ArrayList<>();
        if (content == null) return result;
        String[] lines = content.split("\n", -1);
        for (int i = 0; i < lines.length; i++) {
            Matcher m = TASK_LINE.matcher(lines[i]);
            if (m.matches()) {
                String mark = m.group(2);
                result.add(new TaskItem(m.group(3), i, !mark.equals(" ") && !mark.isEmpty()));
            }
        }
        return result;
    }

    /** 切换指定行的勾选状态，返回新内容；行不是任务行返回 null */
    public static String toggleLine(String content, int lineIndex) {
        if (content == null) return null;
        String[] lines = content.split("\n", -1);
        if (lineIndex < 0 || lineIndex >= lines.length) return null;
        Matcher m = TASK_LINE.matcher(lines[lineIndex]);
        if (!m.matches()) return null;
        String indent = m.group(1);
        String marker = m.group(2);
        String rest = m.group(3);
        boolean checked = !marker.equals(" ") && !marker.isEmpty();
        String newMarker = checked ? " " : "x";
        lines[lineIndex] = indent + "- [" + newMarker + "] " + rest;
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < lines.length; i++) {
            if (i > 0) sb.append('\n');
            sb.append(lines[i]);
        }
        return sb.toString();
    }

    /** 读取文件内容（UTF-8），失败返回 null */
    public static String readFile(File f) {
        try (FileInputStream in = new FileInputStream(f)) {
            StringBuilder sb = new StringBuilder();
            byte[] buf = new byte[8192];
            int n;
            while ((n = in.read(buf)) > 0) {
                sb.append(new String(buf, 0, n, StandardCharsets.UTF_8));
            }
            return sb.toString();
        } catch (Exception e) {
            return null;
        }
    }

    /** 写入文件内容（UTF-8），成功返回 true */
    public static boolean writeFile(File f, String content) {
        try (FileOutputStream out = new FileOutputStream(f)) {
            out.write(content.getBytes(StandardCharsets.UTF_8));
            out.flush();
            return true;
        } catch (Exception e) {
            return false;
        }
    }
}
