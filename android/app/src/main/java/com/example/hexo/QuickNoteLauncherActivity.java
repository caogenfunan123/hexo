package com.example.hexo;

import android.content.Intent;
import android.os.Build;
import android.os.Bundle;

/**
 * 速记中转 Activity（透明，瞬时）：
 *
 * 点击桌面小部件 / 通知栏磁贴时先拉起本 Activity，由它统一做三件事：
 * 1. 检查悬浮窗权限，未授权时跳转系统授权页（一次授权，之后不再打扰）；
 * 2. 通过 startForegroundService 启动 FloatingNoteService 弹出悬浮速记窗；
 * 3. 立即 finish()，屏幕只短暂闪现透明页，不会打开应用主界面。
 *
 * 为什么需要中转 Activity：Android 12+ 对「后台启动前台服务」有严格限制，
 * 部分厂商 ROM（MIUI / HarmonyOS / ColorOS 等）从 AppWidget 直接启动 FGS
 * 会被静默拦截导致点击无反应。经过一次 Activity 中转后属于前台启动，兼容性最好。
 */
public class QuickNoteLauncherActivity extends android.app.Activity {

    private boolean mHandled = false;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        overridePendingTransition(0, 0);

        if (savedInstanceState == null) {
            handleLaunch();
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        // 从授权页返回时再次尝试（首次授权场景）
        if (!mHandled && FloatingNoteService.canDrawOverlays(this)) {
            handleLaunch();
        }
    }

    private void handleLaunch() {
        if (mHandled) return;
        mHandled = true;

        String source = getIntent().getStringExtra(FloatingNoteService.EXTRA_SOURCE);
        if (source == null || source.isEmpty()) source = "widget";

        if (!FloatingNoteService.canDrawOverlays(this)) {
            // 未授权：跳转系统授权页，授权返回后 onResume 会再次尝试
            Intent permIntent = new Intent(
                    android.provider.Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    android.net.Uri.parse("package:" + getPackageName()));
            permIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            try {
                startActivity(permIntent);
            } catch (Exception e) {
                mHandled = false;
            }
            return;
        }

        launchFloating(source);
        finish();
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
            android.util.Log.e("QuickNoteLauncher", "launch floating failed", e);
        }
    }

    @Override
    public void finish() {
        super.finish();
        overridePendingTransition(0, 0);
    }
}
