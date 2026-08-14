package com.example.hexo;

import android.app.PendingIntent;
import android.content.Intent;
import android.os.Build;
import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;

/**
 * 通知栏快捷磁贴：下拉一键速记。
 *
 * 复刻 QuickDaily 思路：点击后收起通知面板并直达速记（Flutter 侧自动聚焦输入框）。
 * Android 14+ 使用 PendingIntent 方式拉起 Activity，兼容高版本系统限制。
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
            Intent intent = QuickNoteIntent.build(this, QuickNoteIntent.MODE_NEW, null);
            // Android 14+：必须使用 PendingIntent 且带 FLAG_IMMUTABLE
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                PendingIntent pi = PendingIntent.getActivity(
                        this,
                        0,
                        intent,
                        PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
                startActivityAndCollapse(pi);
            } else {
                startActivityAndCollapse(intent);
            }
        } catch (Exception e) {
            android.util.Log.e("QuickNoteTile", "launch failed", e);
            try {
                startActivity(QuickNoteIntent.build(this, QuickNoteIntent.MODE_NEW, null));
            } catch (Exception ignored) {
            }
        }
    }
}
