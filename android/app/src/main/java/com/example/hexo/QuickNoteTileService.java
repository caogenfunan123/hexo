package com.example.hexo;

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
            // 磁贴点击 → 透明中转 Activity（权限检查 + startForegroundService 弹出悬浮速记窗）。
            // 中转 Activity 属于前台启动，规避 Android 12+ 从磁贴直接启动 FGS 被拦截的问题。
            Intent launcherIntent = new Intent(this, QuickNoteLauncherActivity.class)
                    .putExtra(FloatingNoteService.EXTRA_SOURCE, "tile")
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivityAndCollapse(launcherIntent);
        } catch (Exception e) {
            android.util.Log.e("QuickNoteTile", "launch failed", e);
            try {
                startActivityAndCollapse(FloatingNoteService.showIntent(this, "tile", null));
            } catch (Exception ignored) {
            }
        }
    }
}
