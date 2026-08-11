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
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity {
    private static final String CHANNEL = "hexo/native";
    private static final int REQ_PICK_IMAGE = 0x4858;
    private static final int REQ_PICK_FILE = 0x4859;
    private static final int REQ_PICK_DIR = 0x4860;
    private MethodChannel.Result pendingPickResult;
    private MethodChannel.Result pendingPickFileResult;
    private MethodChannel.Result pendingPickDirResult;

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
                        default:
                            result.notImplemented();
                    }
                });
    }

    private void openFolder(MethodChannel.MethodCall call, MethodChannel.Result result) {
        try {
            String path = call.argument("path");
            if (path == null || path.isEmpty()) {
                result.error("BAD_PATH", "路径为空", null);
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
                intent = new Intent(Intent.ACTION_VIEW);
                intent.setDataAndType(Environment.getExternalStorageDirectory().toURI()
                        .toString().replace("file:", ""), "resource/folder");
            }
            startActivity(intent);
            result.success(true);
        } catch (Exception e) {
            result.error("OPEN_FAILED", e.getMessage(), null);
        }
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
