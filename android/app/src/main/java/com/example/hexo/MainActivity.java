package com.example.hexo;

import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Intent;
import android.database.Cursor;
import android.net.Uri;
import android.os.Bundle;
import android.os.Environment;
import android.provider.DocumentsContract;
import android.provider.MediaStore;
import android.provider.OpenableColumns;
import android.provider.Settings;
import android.util.Base64;

import androidx.annotation.NonNull;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.HashMap;
import java.util.Map;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity {
    private static final String CHANNEL = "hexo/native";
    private static final String QN_CHANNEL = "hexo/quick_note";
    private static final String FILE_CHANNEL = "hexo/file_open";
    private static final int REQ_PICK_IMAGE = 0x4858;
    private static final int REQ_PICK_FILE = 0x4859;
    private static final int REQ_PICK_DIR = 0x4860;
    private static final int REQ_MANAGE_STORAGE = 0x4861;
    private MethodChannel.Result pendingPickResult;
    private MethodChannel.Result pendingPickFileResult;
    private MethodChannel.Result pendingPickDirResult;
    private MethodChannel.Result pendingManageStorageResult;
    /** 待投递的速记参数缓存（Flutter 拉取后清空） */
    private java.util.Map<String, String> pendingQuickNote;
    /** Flutter 侧监听回调（用于热启动主动推送） */
    private MethodChannel quickNoteChannel;
    /** 外部文件打开缓存：内容 URI 复制到应用私有目录后的路径 */
    private String pendingOpenFilePath;
    /** Flutter 侧文件打开回调通道 */
    private MethodChannel fileOpenChannel;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        // 冷启动：缓存 Intent 中的速记参数，供 Flutter 引擎就绪后拉取
        captureQuickNote(getIntent());
        // 冷启动：缓存外部文件打开 Intent
        captureOpenFile(getIntent());
        // 强制重建全部桌面小部件：
        // APK 升级后系统不会自动刷新已放置的 widget，旧实例仍绑定旧版 PendingIntent（可能指向打开主软件）。
        // 每次打开主应用重建一次，保证点击行为始终与最新代码一致。
        try {
            QuickNoteWidgetProvider.refreshAll(this);
            TaskWidgetProvider.refreshAll(this);
            ReadWidgetProvider.refreshAll(this);
        } catch (Exception e) {
            android.util.Log.w("MainActivity", "refresh widgets failed", e);
        }
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        // 热启动：缓存 + 主动推送速记参数
        boolean captured = captureQuickNote(intent);
        if (captured && quickNoteChannel != null) {
            try {
                quickNoteChannel.invokeMethod("onQuickNote", pendingQuickNote);
                pendingQuickNote = null;
            } catch (Exception e) {
                android.util.Log.d("QuickNote", "push failed, keep cached", e);
            }
        }
        // 热启动：缓存 + 主动推送外部文件打开
        boolean fileCaptured = captureOpenFile(intent);
        if (fileCaptured && fileOpenChannel != null) {
            try {
                fileOpenChannel.invokeMethod("onOpenFile", pendingOpenFilePath);
                pendingOpenFilePath = null;
            } catch (Exception e) {
                android.util.Log.d("FileOpen", "push failed, keep cached", e);
            }
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        // 兜底：onNewIntent 推送时 Flutter 侧监听器可能尚未就绪（冷启动初始化竞态），
        // 消息发出后无人消费 → pendingQuickNote 已置 null 造成"死缓存"。
        // 恢复前台时若仍有缓存则重推一次；Dart 侧 resumed 也会主动 fetch 兜底。
        if (pendingQuickNote != null && pendingQuickNote.size() > 0 && quickNoteChannel != null) {
            try {
                quickNoteChannel.invokeMethod("onQuickNote", pendingQuickNote);
                pendingQuickNote = null;
            } catch (Exception e) {
                android.util.Log.d("QuickNote", "resume push failed, keep cached", e);
            }
        }
        // 文件打开同样兜底重推
        if (pendingOpenFilePath != null && fileOpenChannel != null) {
            try {
                fileOpenChannel.invokeMethod("onOpenFile", pendingOpenFilePath);
                pendingOpenFilePath = null;
            } catch (Exception e) {
                android.util.Log.d("FileOpen", "resume push failed, keep cached", e);
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

    /** 从 ACTION_VIEW Intent 读取外部文件，复制到应用缓存目录，返回是否成功 */
    private boolean captureOpenFile(Intent intent) {
        if (intent == null) return false;
        if (!Intent.ACTION_VIEW.equals(intent.getAction())) return false;
        Uri uri = intent.getData();
        if (uri == null) return false;
        try {
            // 读取文件显示名称
            String name = queryName(uri);
            if (name == null) name = "untitled.md";
            // 复制到应用私有缓存目录
            java.io.File cacheDir = getCacheDir();
            java.io.File target = new java.io.File(cacheDir, name);
            try (InputStream in = getContentResolver().openInputStream(uri);
                 java.io.FileOutputStream out = new java.io.FileOutputStream(target)) {
                if (in == null) return false;
                byte[] buf = new byte[8192];
                int n;
                while ((n = in.read(buf)) >= 0) {
                    out.write(buf, 0, n);
                }
            }
            pendingOpenFilePath = target.getAbsolutePath();
            return true;
        } catch (Exception e) {
            android.util.Log.w("FileOpen", "capture failed", e);
            return false;
        }
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
                        case "isAppPrivatePath": {
                            String p = call.argument("path");
                            result.success(p != null && isAppPrivatePath(p));
                            break;
                        }
                        case "getLaunchQuickNote":
                            // 拉取并清空缓存的速记参数
                            java.util.Map<String, String> cached = pendingQuickNote;
                            pendingQuickNote = null;
                            result.success(cached);
                            break;
                        case "getPendingOpenFile":
                            // 拉取并清空缓存的外部文件路径
                            String p1 = pendingOpenFilePath;
                            pendingOpenFilePath = null;
                            result.success(p1);
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
                        case "checkManageStoragePermission":
                            // Android 11+: 检查是否有"所有文件访问"权限
                            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                                result.success(Environment.isExternalStorageManager());
                            } else {
                                // Android 10 及以下：已有 READ/WRITE_EXTERNAL_STORAGE 即可
                                result.success(true);
                            }
                            break;
                        case "requestManageStoragePermission":
                            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                                if (Environment.isExternalStorageManager()) {
                                    result.success(true);
                                } else {
                                    if (pendingManageStorageResult != null) {
                                        result.error("BUSY", "已有权限请求进行中", null);
                                        return;
                                    }
                                    pendingManageStorageResult = result;
                                    try {
                                        Intent intent = new Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION);
                                        intent.setData(Uri.parse("package:" + getPackageName()));
                                        startActivityForResult(intent, REQ_MANAGE_STORAGE);
                                    } catch (Exception e) {
                                        pendingManageStorageResult = null;
                                        result.error("REQUEST_FAILED", e.getMessage(), null);
                                    }
                                }
                            } else {
                                // Android 10 及以下不需要此权限
                                result.success(true);
                            }
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
                                } else if ("quick_note".equals(w)) {
                                    QuickNoteWidgetProvider.refreshAll(this);
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
                        case "getExportDir":
                            result.success(getPublicDocumentsDir());
                            break;
                        case "convertTreeUriToPath": {
                            String treeUriStr = call.argument("treeUri");
                            result.success(treeUriStr != null ? treeUriToPath(treeUriStr) : null);
                            break;
                        }
                        case "exportFile": {
                            String sourcePath = call.argument("sourcePath");
                            String fileName = call.argument("fileName");
                            if (sourcePath == null || fileName == null) {
                                result.error("INVALID_ARGS", "sourcePath and fileName required", null);
                                return;
                            }
                            try {
                                String exported;
                                if (android.os.Build.VERSION.SDK_INT >= 29) {
                                    exported = exportFileToDownloadsMediaStore(sourcePath, fileName);
                                } else {
                                    exported = exportFileToDownloadsLegacy(sourcePath, fileName);
                                }
                                if (exported != null) {
                                    result.success(exported);
                                } else {
                                    result.error("EXPORT_FAILED", "export returned null", null);
                                }
                            } catch (Exception e) {
                                result.error("EXPORT_FAILED", e.getMessage(), null);
                            }
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

        // 原生 → Flutter 反向通道：热启动时主动推送外部文件打开
        fileOpenChannel = new MethodChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(), FILE_CHANNEL);
        fileOpenChannel.setMethodCallHandler((call, result) -> {
            if ("getPendingOpenFile".equals(call.method)) {
                String cachedPath = pendingOpenFilePath;
                pendingOpenFilePath = null;
                result.success(cachedPath);
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
        } else if (requestCode == REQ_MANAGE_STORAGE && pendingManageStorageResult != null) {
            MethodChannel.Result result = pendingManageStorageResult;
            pendingManageStorageResult = null;
            // 用户从设置页面返回，重新检查权限状态
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                result.success(Environment.isExternalStorageManager());
            } else {
                result.success(true);
            }
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

    /** 将 SAF tree URI（如 content://.../tree/primary%3ADocuments%2FTuomo）转换为真实物理路径 */
    private String treeUriToPath(String treeUri) {
        try {
            Uri uri = Uri.parse(treeUri);
            String docId = DocumentsContract.getTreeDocumentId(uri);
            // "primary:Documents/Tuomo" 或 "ABCD-1234:foo"
            String[] parts = docId.split(":", 2);
            String type = parts[0];
            String relativePath = parts.length > 1 ? parts[1] : "";
            if ("primary".equals(type)) {
                return Environment.getExternalStorageDirectory().getAbsolutePath() + "/" + relativePath;
            }
            // 非主存储（SD 卡）
            java.io.File[] dirs = getExternalFilesDirs(null);
            for (java.io.File d : dirs) {
                if (d != null && d.getAbsolutePath().contains(type)) {
                    String extPath = d.getAbsolutePath();
                    int idx = extPath.indexOf("/Android/data/");
                    if (idx > 0) extPath = extPath.substring(0, idx);
                    return extPath + "/" + relativePath;
                }
            }
        } catch (Exception e) {
            android.util.Log.w("Main", "treeUriToPath failed", e);
        }
        return null;
    }

    /** 通过 MediaStore Downloads 将文件导出到用户可见的下载目录（Android 10+），返回 content:// URI */
    private String exportFileToDownloadsMediaStore(String sourcePath, String fileName) throws Exception {
        java.io.File src = new java.io.File(sourcePath);
        if (!src.exists()) return null;
        byte[] content = new byte[(int) src.length()];
        try (FileInputStream fis = new FileInputStream(src)) {
            int offset = 0;
            while (offset < content.length) {
                int n = fis.read(content, offset, content.length - offset);
                if (n < 0) break;
                offset += n;
            }
        }

        ContentValues values = new ContentValues();
        values.put(MediaStore.Downloads.DISPLAY_NAME, fileName);
        values.put(MediaStore.Downloads.MIME_TYPE, "text/markdown");
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
            values.put(MediaStore.Downloads.IS_PENDING, 1);
        }

        Uri uri = getContentResolver().insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values);
        if (uri == null) return null;

        try (OutputStream out = getContentResolver().openOutputStream(uri)) {
            if (out == null) return null;
            out.write(content);
        }

        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
            values.clear();
            values.put(MediaStore.Downloads.IS_PENDING, 0);
            getContentResolver().update(uri, values, null, null);
        }

        return uri.toString();
    }

    /** Android 9-：直接写入外部存储 Download 目录 */
    private String exportFileToDownloadsLegacy(String sourcePath, String fileName) throws Exception {
        java.io.File src = new java.io.File(sourcePath);
        if (!src.exists()) return null;
        java.io.File dest = new java.io.File(
                Environment.getExternalStorageDirectory(), "Download/" + fileName);
        try (FileInputStream fis = new FileInputStream(src);
             java.io.FileOutputStream fos = new java.io.FileOutputStream(dest)) {
            byte[] buf = new byte[8192];
            int n;
            while ((n = fis.read(buf)) >= 0) {
                fos.write(buf, 0, n);
            }
        }
        return dest.getAbsolutePath();
    }
}
