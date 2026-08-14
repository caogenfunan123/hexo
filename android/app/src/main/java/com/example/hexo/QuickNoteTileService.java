package com.example.hexo;

import android.app.PendingIntent;
import android.content.Intent;
import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;

/**
 * 通知栏快捷磁贴：下拉一键速记。
 *
 * 复刻 QuickDaily 思路：点击后收起通知面板并启动原生悬浮速记窗。
 * 只出悬浮窗、不打开主界面（除非缺少悬浮窗权限）。
 */
public class QuickNoteTileService extends TileService {

    @Override
    public void onTileAdded() {
        updateTileState();
    }

    @Override
    public void onStartListening() {
        updateTileState();
    }

    private void updateTileState() {
        Tile tile = getQsTile();
        if (tile != null) {
            tile.setLabel("速记");
            tile.setState(Tile.STATE_ACTIVE);
            tile.updateTile();
        }
    }

    @Override
    public void onClick() {
        super.onClick();
        updateTileState();
        try {
            Intent serviceIntent = FloatingNoteService.showIntent(this, "tile", null);
            // 前台服务必须用 getForegroundService，避免 Android 8+ 后台启动被拦截
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                PendingIntent pi = PendingIntent.getForegroundService(
                        this,
                        0,
                        serviceIntent,
                        PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
                startActivityAndCollapse(pi);
            } else {
                startActivityAndCollapse(serviceIntent);
            }
        } catch (Exception e) {
            android.util.Log.e("QuickNoteTile", "launch failed", e);
            try {
                startForegroundService(FloatingNoteService.showIntent(this, "tile", null));
            } catch (Exception ignored) {
            }
        }
    }
}
