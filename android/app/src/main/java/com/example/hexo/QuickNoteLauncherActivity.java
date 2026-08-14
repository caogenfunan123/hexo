package com.example.hexo;

import android.content.Intent;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.widget.Toast;

/**
 * 速记中转 Activity（透明，瞬时）：
 *
 * 点击桌面小部件 / 通知栏磁贴时先拉起本 Activity，由它统一做三件事：
 * 1. 检查悬浮窗权限，未授权时跳转系统授权页（授权返回后自动重试启动悬浮窗）；
 * 2. 通过 startForegroundService 启动 FloatingNoteService 弹出悬浮速记窗；
 * 3. 延迟 finish()，屏幕只短暂闪现透明页，不会打开应用主界面。
 *
 * 为什么需要中转 Activity：Android 12+ 对「后台启动前台服务」有严格限制，
 * 部分厂商 ROM（MIUI / HarmonyOS / ColorOS 等）从 AppWidget 直接启动 FGS
 * 会被静默拦截导致点击无反应。经过一次 Activity 中转后属于前台启动，兼容性最好。
 */
public class QuickNoteLauncherActivity extends android.app.Activity {

    private static final String TAG = "QuickNoteLauncher";
    private static final int REQ_OVERLAY_PERMISSION = 0x0001;

    private boolean mHandled = false;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        overridePendingTransition(0, 0);

        Log.d(TAG, "onCreate canDrawOverlays=" + FloatingNoteService.canDrawOverlays(this));

        if (savedInstanceState == null) {
            handleLaunch();
        }
    }

    private void handleLaunch() {
        if (mHandled) return;

        String source = getIntent().getStringExtra(FloatingNoteService.EXTRA_SOURCE);
        if (source == null || source.isEmpty()) source = "widget";

        if (!FloatingNoteService.canDrawOverlays(this)) {
            // 未授权：跳转系统授权页，返回后由 onActivityResult 统一处理
            // 此处不置 mHandled，授权成功返回后会自动重试启动悬浮窗
            Intent permIntent = new Intent(
                    android.provider.Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    android.net.Uri.parse("package:" + getPackageName()));
            permIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            try {
                startActivityForResult(permIntent, REQ_OVERLAY_PERMISSION);
            } catch (Exception e) {
                Log.e(TAG, "open overlay permission page failed", e);
                Toast.makeText(this, "请在系统设置中开启悬浮窗权限", Toast.LENGTH_LONG).show();
                finish();
            }
            return;
        }

        mHandled = true;
        launchFloating(source);
        // 延迟 finish：让前台服务完成前台启动，规避部分 ROM 滞后校验「后台启动 FGS」限制
        new Handler(Looper.getMainLooper()).postDelayed(this::finish, 400);
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == REQ_OVERLAY_PERMISSION) {
            Log.d(TAG, "returned from permission page canDrawOverlays="
                    + FloatingNoteService.canDrawOverlays(this));
            if (FloatingNoteService.canDrawOverlays(this)) {
                handleLaunch();
            } else {
                // 用户未授权直接返回：结束透明页，下次点击再引导
                finish();
            }
        }
    }

    private void launchFloating(String source) {
        Intent serviceIntent = FloatingNoteService.showIntent(this, source, null);
        try {
            // Activity 在前台，此时启动前台服务属于允许的前台启动路径
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent);
            } else {
                startService(serviceIntent);
            }
        } catch (Exception e) {
            Log.e(TAG, "launch floating failed", e);
            Toast.makeText(this, "启动速记窗失败，请检查悬浮窗与后台弹出权限", Toast.LENGTH_LONG).show();
            finish();
        }
    }

    @Override
    public void finish() {
        super.finish();
        overridePendingTransition(0, 0);
    }
}
