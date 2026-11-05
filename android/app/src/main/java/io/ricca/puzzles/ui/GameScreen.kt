package io.ricca.puzzles.ui

import android.view.ViewGroup
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import io.ricca.puzzles.GameController
import io.ricca.puzzles.Sheet

@Composable
fun GameScreen(c: GameController, onBack: () -> Unit) {
    val t = T
    val cur = c.cur ?: return
    Column(Modifier.fillMaxSize()) {
        // ---- top bar ----
        Row(Modifier.fillMaxWidth().heightIn(min = 64.dp).padding(horizontal = 10.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            IconSlab(Icons.Back, "Back to puzzles", onBack)
            Column(Modifier.weight(1f).clip(RoundedCornerShape(8.dp)).clickable { c.sheet = Sheet.Types }
                .padding(horizontal = 4.dp, vertical = 2.dp)) {
                Text(cur.def.title.uppercase(), style = heavy(22, t.text), maxLines = 1)
                Text(c.label, color = t.text2, fontFamily = Mono, fontSize = 12.sp, fontWeight = FontWeight.SemiBold,
                    maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            if (c.showTimer && !t.eink) {
                Text(GameController.fmtTime(c.elapsed.toDouble()),
                    Modifier.background(t.surface, RoundedCornerShape(6.dp)).border(t.border, t.ink, RoundedCornerShape(6.dp))
                        .padding(horizontal = 6.dp, vertical = 3.dp),
                    color = t.text, fontFamily = Mono, fontWeight = FontWeight.Bold, fontSize = 14.sp)
            }
            if (c.canZoom) {
                IconSlab(Icons.ZoomOut, "Zoom out", c::zoomOut, enabled = c.canZoomOut)
                IconSlab(Icons.ZoomIn, "Zoom in", c::zoomIn, enabled = c.canZoomIn)
            }
            IconSlab(Icons.Menu, "Menu", { c.sheet = Sheet.Menu }, color = t.accent, tint = t.accentText)
        }

        if (c.statusText.isNotEmpty()) {
            Text(c.statusText,
                Modifier.padding(start = 12.dp, end = 12.dp, bottom = 8.dp).fillMaxWidth()
                    .background(t.surface, RoundedCornerShape(6.dp)).border(t.border, t.ink, RoundedCornerShape(6.dp))
                    .padding(horizontal = 10.dp, vertical = 6.dp),
                color = t.text, fontFamily = Mono, fontSize = 13.sp, fontWeight = FontWeight.Bold,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        }

        // ---- board ----
        val shape = RoundedCornerShape(10.dp)
        Box(
            Modifier.weight(1f).fillMaxWidth()
                .padding(start = 12.dp, end = 12.dp + t.off, bottom = 8.dp + t.off)
                .drawBehind {
                    val o = t.off.toPx()
                    drawRoundRect(t.ink, Offset(o, o), size, CornerRadius(10.dp.toPx()))
                }
                .background(Color(c.boardBg), shape)
                .border(t.border, t.ink, shape)
                .padding(t.border)
                .clip(RoundedCornerShape(7.dp)),
        ) {
            AndroidView(
                factory = { (c.board.parent as? ViewGroup)?.removeView(c.board); c.board },
                modifier = Modifier.fillMaxSize(),
            )
            c.busy?.let { msg ->
                Row(Modifier.fillMaxSize().background(Color(c.boardBg)).clickable(enabled = false) {},
                    horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                    if (!t.eink) Box(Modifier.size(22.dp).background(t.accent, RoundedCornerShape(4.dp))
                        .border(t.border, Color(0xFF111111), RoundedCornerShape(4.dp)))
                    Spacer(Modifier.width(12.dp))
                    Text(msg.uppercase(), color = if (t.dark) Color(0xFFF6EFDF) else Color(0xFF111111),
                        fontWeight = FontWeight.ExtraBold, fontSize = 14.sp, letterSpacing = 0.6.sp)
                }
            }
        }

        // ---- solved banner ----
        c.solvedText?.let { msg ->
            Slab(Modifier.padding(start = 12.dp, end = 12.dp + t.off, bottom = 8.dp + t.off).fillMaxWidth(),
                color = t.accent, contentAlignment = Alignment.CenterStart) {
                Row(Modifier.padding(start = 16.dp, end = 10.dp, top = 10.dp, bottom = 10.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    Text(msg.uppercase(), Modifier.weight(1f), style = heavy(18, t.accentText))
                    Btn("New game", primary = true) { c.newGame() }
                }
            }
        }

        // ---- bottom controls ----
        Column(Modifier.fillMaxWidth().padding(start = 12.dp, end = 12.dp, top = 4.dp, bottom = 12.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (c.keys.isNotEmpty()) Keypad(c)
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (cur.def.modes.size >= 2) Segmented(cur.def.modes.map { it.label }, c.mode, c::selectMode)
                Spacer(Modifier.weight(1f))
                IconSlab(Icons.Undo, "Undo", { c.sendKey(io.ricca.puzzles.Btn.UI_UNDO) }, size = 52.dp, shadow = t.off, enabled = c.canUndo)
                Spacer(Modifier.width(12.dp))
                IconSlab(Icons.Redo, "Redo", { c.sendKey(io.ricca.puzzles.Btn.UI_REDO) }, size = 52.dp, shadow = t.off, enabled = c.canRedo)
                Spacer(Modifier.width(t.off))
            }
        }
    }
}

@Composable
private fun Segmented(labels: List<String>, selected: Int, onSelect: (Int) -> Unit) {
    val t = T
    Slab(radius = 10.dp) {
        Row(Modifier.height(IntrinsicSize.Min).padding(t.border).clip(RoundedCornerShape(7.dp))) {
            labels.forEachIndexed { i, l ->
                if (i > 0) Box(Modifier.width(t.border).fillMaxHeight().background(t.ink))
                val on = i == selected
                val bg = when { !on -> Color.Transparent; t.eink -> Color.Black; else -> t.accent }
                val fg = when { !on -> t.text; t.eink -> Color.White; else -> t.accentText }
                Box(Modifier.widthIn(min = 72.dp).height(46.dp).background(bg).clickable { onSelect(i) }
                    .padding(horizontal = 16.dp), contentAlignment = Alignment.Center) {
                    Text(l.uppercase(), color = fg, fontWeight = FontWeight.ExtraBold, fontSize = 14.sp, letterSpacing = 0.5.sp)
                }
            }
        }
    }
}

@Composable
private fun Keypad(c: GameController) {
    val t = T
    Row(Modifier.fillMaxWidth().padding(end = 2.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        for (k in c.keys) {
            Slab(Modifier.weight(1f).height(50.dp), radius = 8.dp, shadow = 2.dp,
                color = if (c.keypadNotes) t.surface2 else t.surface, onClick = { c.sendKey(k.button) }) {
                if (k.button == 8 || k.button == 127) Icon(Icons.Backspace, "Clear", Modifier.size(24.dp), tint = t.text)
                else Text(k.label, color = t.text, fontWeight = FontWeight.Black, fontSize = if (c.keypadNotes) 15.sp else 22.sp)
            }
        }
    }
}

@Composable
fun Btn(label: String, primary: Boolean = false, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val t = T
    Slab(modifier.height(48.dp), radius = 8.dp, shadow = 3.dp, color = if (primary) t.pop else t.surface, onClick = onClick) {
        Text(label.uppercase(), Modifier.padding(horizontal = 22.dp), color = if (primary) t.popText else t.text,
            fontWeight = FontWeight.Black, fontSize = 15.sp, letterSpacing = 0.6.sp)
    }
}
