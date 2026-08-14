package com.example.hexo;

import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;

/**
 * 通知栏快捷磁贴：下拉一键速记。
 *
 * 点击 → 拉起主界面并进入新建草稿。无输入框，保持极简（参考 QuickDaily 快捷磁贴思路）。
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
        updateTileState();
        try {
            startActivityAndCollapse(
                    QuickNoteIntent.build(this, QuickNoteIntent.MODE_NEW, null));
        } catch (Exception e) {
            android.util.Log.e("QuickNoteTile", "launch failed", e);
        }
    }
}
