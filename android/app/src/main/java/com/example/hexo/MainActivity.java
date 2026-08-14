package com.example.hexo;

import android.content.ContentResolver;
import android.content.Intent;
import android.database.Cursor;
import android.net.Uri;
import android.os.Bundle;
import android.os.Environment;
import android.provider.OpenableColumns;
import android.util.Base64;

import androidx.annotation.NonNull;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.util.HashMap;
import java.util.Map;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity {
    private static final String CHANNEL = "hexo/native";
    private static final String QN_CHANNEL = "hexo/quick_note";
    private static final int REQ_PICK_IMAGE = 0x4858;
    private static final int REQ_PICK_FILE = 0x4859;
    private static final int REQ_PICK_DIR = 0x4860;
    private MethodChannel.Result pendingPickResult;
    private MethodChannel.Result pendingPickFileResult;
    private MethodChannel.Result pendingPickDirResult;
    /** 待投递的速记参数缓存（Flutter 拉取后清空） */
    private java.util.Map<String, String> pendingQuickNote;
    /** Flutter 侧监听回调（用于热启动主动推送） */
    private MethodChannel quickNoteChannel;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        // 冷启动：缓存 Intent 中的速记参数，供 Flutter 引擎就绪后拉取
        captureQuickNote(getIntent());
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        // 热启动：缓存 + 主动推送
        boolean captured = captureQuickNote(intent);
        if (captured && quickNoteChannel != null) {
            try {
                quickNoteChannel.invokeMethod("onQuickNote", pendingQuickNote);
                pendingQuickNote = null;
            } catch (Exception e) {
                android.util.Log.d("QuickNote", "push failed, keep cached", e);
            }
        }
    }

    /** 从 Intent 提取速记参数存入缓存，返回是否携带 */
    private boolean captureQuickNote(Intent intent) {
        if (intent == null) return false;
        String mode = intent.getStringExtra(QuickNoteIntent.EXTRA_MODE);
        if (mode == null) return false;
        java.util.Map<String, String> data = new java.util.HashMap<>();
        data.put("mode", mode);
        String text = intent.getStringExtra(QuickNoteIntent.EXTRA_TEXT);
        if (text != null && !text.isEmpty()) {
            data.put("text", text);
        }
        String path = intent.getStringExtra(QuickNoteIntent.EXTRA_PATH);
        if (path != null && !path.isEmpty()) {
            data.put("path", path);
        }
        pendingQuickNote = data;
        return true;
    }

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL)
                .setMethodCallHandler((call, result) -> {
                    switch (call.method) {
                        case "getFilesDir":
                            result.success(getFilesDir().getAbsolutePath());
                            break;
                        case "getExternalFilesDir":
                            result.success(getExternalFilesDir(null) != null
                                    ? getExternalFilesDir(null).getAbsolutePath()
                                    : getFilesDir().getAbsolutePath());
                            break;
                        case "getPublicDocumentsDir":
                            result.success(getPublicDocumentsDir());
                            break;
                        case "isAppPrivatePath":
                            String p = call.argument("path");
                            result.success(p != null && isAppPrivatePath(p));
                            break;
                        case "getLaunchQuickNote":
                            // 拉取并清空缓存的速记参数
                            java.util.Map<String, String> cached = pendingQuickNote;
                            pendingQuickNote = null;
                            result.success(cached);
                            break;
                        case "pickImage":
                            if (pendingPickResult != null) {
                                result.error("BUSY", "已有选图任务", null);
                                return;
                            }
                            pendingPickResult = result;
                            try {
                                Intent intent = new Intent(Intent.ACTION_GET_CONTENT);
                                intent.addCategory(Intent.CATEGORY_OPENABLE);
                                intent.setType("image/*");
                                startActivityForResult(Intent.createChooser(intent, "选择图片"), REQ_PICK_IMAGE);
                            } catch (Exception e) {
                                pendingPickResult = null;
                                result.error("PICK_FAILED", e.getMessage(), null);
                            }
                            break;
                        case "pickFile":
                            if (pendingPickFileResult != null) {
                                result.error("BUSY", "已有选文件任务", null);
                                return;
                            }
                            pendingPickFileResult = result;
                            try {
                                Intent intent = new Intent(Intent.ACTION_GET_CONTENT);
                                intent.addCategory(Intent.CATEGORY_OPENABLE);
                                intent.setType("text/markdown");
                                startActivityForResult(Intent.createChooser(intent, "选择 .md 文件"), REQ_PICK_FILE);
                            } catch (Exception e) {
                                pendingPickFileResult = null;
                                result.error("PICK_FAILED", e.getMessage(), null);
                            }
                            break;
                        case "pickDirectory":
                            if (pendingPickDirResult != null) {
                                result.error("BUSY", "已有选目录任务", null);
                                return;
                            }
                            pendingPickDirResult = result;
                            try {
                                Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT_TREE);
                                startActivityForResult(intent, REQ_PICK_DIR);
                            } catch (Exception e) {
                                pendingPickDirResult = null;
                                result.error("PICK_FAILED", e.getMessage(), null);
                            }
                            break;
                        case "checkStoragePermission":
                            // Android 11+ 分区存储：应用私有目录始终可写
                            result.success(true);
                            break;
                        case "openFolder":
                            openFolder(call, result);
                            break;
                        case "setWidgetArticlePath": {
                            String p = call.argument("path");
                            String w = call.argument("widget");
                            result.success(NativeQuickNoteStore.setSelectedArticlePath(this,
                                    w == null ? "read" : w, p));
                            break;
                        }
                        case "listNativeMds":
                            result.success(NativeQuickNoteStore.listAllMdPaths(this));
                            break;
                        case "refreshWidget": {
                            String w = call.argument("widget");
                            if (w == null) w = "read";
                            boolean ok = false;
                            try {
                                if ("task".equals(w)) {
                                    TaskWidgetProvider.refreshAll(this);
                                } else {
                                    ReadWidgetProvider.refreshAll(this);
                                }
                                ok = true;
                            } catch (Exception e) {
                                android.util.Log.e("Main", "refresh widget failed", e);
                            }
                            result.success(ok);
                            break;
                        }
                        default:
                            result.notImplemented();
                    }
                });

        // 原生 → Flutter 反向通道：热启动时主动推送速记参数
        quickNoteChannel = new MethodChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(), QN_CHANNEL);
        quickNoteChannel.setMethodCallHandler((call, result) -> {
            if ("getLaunchQuickNote".equals(call.method)) {
                java.util.Map<String, String> cached = pendingQuickNote;
                pendingQuickNote = null;
                result.success(cached);
            } else {
                result.notImplemented();
            }
        });
    }

    private void openFolder(MethodCall call, MethodChannel.Result result) {
        try {
            String path = call.argument("path");
            if (path == null || path.isEmpty()) {
                result.error("BAD_PATH", "路径为空", null);
                return;
            }
            // Android 11+ 沙盒：应用私有目录（Android/data、Android/obb）
            // 无法通过 Intent 交给外部文件管理器打开
            if (isAppPrivatePath(path)) {
                result.error(
                        "PRIVATE_PATH",
                        "应用私有目录，系统文件管理器无法打开，请在应用内查看",
                        null);
                return;
            }
            Uri uri = Uri.parse(path);
            if (uri.getScheme() == null || uri.getScheme().equals("file")) {
                java.io.File dir = new java.io.File(path);
                if (!dir.exists()) {
                    dir.mkdirs();
                }
                uri = Uri.fromFile(dir);
            }
            Intent intent = new Intent(Intent.ACTION_VIEW);
            intent.setDataAndType(uri, "resource/folder");
            if (intent.resolveActivity(getPackageManager()) == null) {
                // 无文件夹查看器时退回文件管理器根部
                Intent fallback = new Intent(Intent.ACTION_VIEW);
                fallback.setDataAndType(
                        Uri.parse(Environment.getExternalStorageDirectory().getAbsolutePath()),
                        "resource/folder");
                intent = fallback;
            }
            startActivity(intent);
            result.success(true);
        } catch (Exception e) {
            result.error("OPEN_FAILED", e.getMessage(), null);
        }
    }

    /** 判断是否为 Android 应用私有沙盒路径（外部文件管理器无法打开） */
    private boolean isAppPrivatePath(String path) {
        String p = path.toLowerCase();
        return p.contains("/android/data/")
                || p.startsWith("/android/data")
                || p.contains("/android/obb/")
                || p.startsWith("/android/obb");
    }

    /** 获取公共 Documents 目录下的应用目录（/storage/emulated/0/Documents/Tuomo） */
    private String getPublicDocumentsDir() {
        java.io.File dir = new java.io.File(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS),
                "Tuomo");
        if (!dir.exists()) {
            dir.mkdirs();
        }
        return dir.getAbsolutePath();
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == REQ_PICK_IMAGE && pendingPickResult != null) {
            MethodChannel.Result result = pendingPickResult;
            pendingPickResult = null;
            if (resultCode != RESULT_OK || data == null || data.getData() == null) {
                result.success(null);
                return;
            }
            Uri uri = data.getData();
            try {
                byte[] bytes = readAll(uri);
                String name = queryName(uri);
                Map<String, Object> map = new HashMap<>();
                map.put("base64", Base64.encodeToString(bytes, Base64.NO_WRAP));
                map.put("name", name == null ? "image.jpg" : name);
                map.put("size", bytes.length);
                result.success(map);
            } catch (Exception e) {
                result.error("READ_FAILED", e.getMessage(), null);
            }
        } else if (requestCode == REQ_PICK_FILE && pendingPickFileResult != null) {
            MethodChannel.Result result = pendingPickFileResult;
            pendingPickFileResult = null;
            if (resultCode != RESULT_OK || data == null || data.getData() == null) {
                result.success(null);
                return;
            }
            Uri uri = data.getData();
            try {
                byte[] bytes = readAll(uri);
                String name = queryName(uri);
                Map<String, Object> map = new HashMap<>();
                map.put("base64", Base64.encodeToString(bytes, Base64.NO_WRAP));
                map.put("name", name == null ? "untitled.md" : name);
                result.success(map);
            } catch (Exception e) {
                result.error("READ_FAILED", e.getMessage(), null);
            }
        } else if (requestCode == REQ_PICK_DIR && pendingPickDirResult != null) {
            MethodChannel.Result result = pendingPickDirResult;
            pendingPickDirResult = null;
            if (resultCode != RESULT_OK || data == null || data.getData() == null) {
                result.success(null);
                return;
            }
            Uri uri = data.getData();
            // ACTION_OPEN_DOCUMENT_TREE 返回 tree:// URI；取文档路径作为可写目录
            String treePath = uri.toString();
            result.success(treePath);
        }
    }

    private byte[] readAll(Uri uri) throws Exception {
        ContentResolver resolver = getContentResolver();
        try (InputStream in = resolver.openInputStream(uri);
             ByteArrayOutputStream out = new ByteArrayOutputStream()) {
            if (in == null) throw new IllegalStateException("无法打开图片");
            byte[] buf = new byte[8192];
            int n;
            while ((n = in.read(buf)) >= 0) {
                out.write(buf, 0, n);
            }
            return out.toByteArray();
        }
    }

    private String queryName(Uri uri) {
        Cursor cursor = null;
        try {
            cursor = getContentResolver().query(uri, null, null, null, null);
            if (cursor != null && cursor.moveToFirst()) {
                int idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME);
                if (idx >= 0) return cursor.getString(idx);
            }
        } catch (Exception ignored) {
        } finally {
            if (cursor != null) cursor.close();
        }
        return null;
    }
}
